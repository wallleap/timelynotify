import { common } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { EncryptionConfig } from '../model/EncryptionConfig';
import { PreferencesUtil } from '../utils/PreferencesUtil';
import { EncryptionKeyStoreService } from './EncryptionKeyStoreService';

const KEY_SERVER_ENCRYPTION_CONFIGS: string = 'server_encryption_configs';
// 64 个单字节可打印字符，随机字节取低 6 位时分布均匀，生成结果便于复制到发送端。
const GENERATED_KEY_CHARACTERS: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

class StoredEncryptionConfig extends Object {
  enabled: boolean = false;
  algorithm: string = 'AES128';
  mode: string = 'CBC';
  padding: string = 'PKCS7';
  deviceKey: string = '';
}

// 加密配置单独持久化，避免密钥混入服务器列表、复制地址或其它导出路径。
export class EncryptionConfigService {
  static expectedKeyBytes(algorithm: string): number {
    if (algorithm === 'AES192') {
      return 24;
    }
    if (algorithm === 'AES256') {
      return 32;
    }
    return 16;
  }

  static utf8Length(value: string): number {
    return util.TextEncoder.create('utf-8').encodeInto(value).length;
  }

  /** 使用系统密码学安全随机数生成与当前 AES 算法长度匹配的可打印 Key。 */
  static generateKey(algorithm: string): string {
    if (!canIUse('SystemCapability.Security.CryptoFramework.Rand')) {
      throw new Error('当前设备不支持安全随机数生成');
    }
    const length: number = EncryptionConfigService.expectedKeyBytes(algorithm);
    try {
      // @SuppressWarnings syscap
      const random: cryptoFramework.Random = cryptoFramework.createRandom();
      // @SuppressWarnings syscap
      const randomBytes: Uint8Array = random.generateRandomSync(length).data;
      let result: string = '';
      for (let i: number = 0; i < randomBytes.length; i++) {
        result += GENERATED_KEY_CHARACTERS.charAt(randomBytes[i] & 63);
      }
      return result;
    } catch (_err) {
      throw new Error('安全随机 Key 生成失败');
    }
  }

  static validate(config: EncryptionConfig): string {
    if (!config.enabled) {
      return '';
    }
    if (config.algorithm !== 'AES128' && config.algorithm !== 'AES192' && config.algorithm !== 'AES256') {
      return '不支持的 AES 算法';
    }
    if (config.mode !== 'CBC' && config.mode !== 'ECB' && config.mode !== 'GCM') {
      return '不支持的加密模式';
    }
    const expected: number = EncryptionConfigService.expectedKeyBytes(config.algorithm);
    if (EncryptionConfigService.utf8Length(config.key) !== expected) {
      return `Key 必须为 ${expected} 个 UTF-8 字节`;
    }
    const expectedPadding: string = config.mode === 'GCM' ? 'NoPadding' : 'PKCS7';
    if (config.padding !== expectedPadding) {
      return `${config.mode} 必须使用 ${expectedPadding}`;
    }
    return '';
  }

  static async get(context: common.Context | null, serverId: string): Promise<EncryptionConfig> {
    const configs: Record<string, EncryptionConfig> = await EncryptionConfigService.load(context);
    return configs[serverId] || new EncryptionConfig();
  }

  static async findByDeviceKey(context: common.Context | null, deviceKey: string): Promise<EncryptionConfig | null> {
    const configs: Record<string, EncryptionConfig> = await EncryptionConfigService.load(context);
    const ids: string[] = Object.keys(configs);
    for (let i: number = 0; i < ids.length; i++) {
      const config: EncryptionConfig = configs[ids[i]];
      if (config.enabled && config.deviceKey === deviceKey) {
        return config;
      }
    }
    return null;
  }

  static async save(context: common.Context | null, serverId: string,
    config: EncryptionConfig): Promise<boolean> {
    const error: string = EncryptionConfigService.validate(config);
    if (error.length > 0) {
      return false;
    }
    // 先读取并完成旧版明文 Key 迁移，再写入用户本次提交的 Key，避免迁移值覆盖新值。
    const configs: Record<string, EncryptionConfig> = await EncryptionConfigService.load(context);
    if (config.key.length > 0 && !await EncryptionKeyStoreService.put(serverId, config.key)) {
      return false;
    }
    configs[serverId] = config;
    return EncryptionConfigService.persistMetadata(context, configs);
  }

  static async remove(context: common.Context | null, serverId: string): Promise<boolean> {
    // 必须先读取配置；否则旧版 Preferences 中的明文 Key 会在删除安全资产后被迁移回来。
    const configs: Record<string, EncryptionConfig> = await EncryptionConfigService.load(context);
    if (!await EncryptionKeyStoreService.remove(serverId)) {
      return false;
    }
    const remaining: Record<string, EncryptionConfig> = {};
    const ids: string[] = Object.keys(configs);
    for (let i: number = 0; i < ids.length; i++) {
      if (ids[i] !== serverId) {
        remaining[ids[i]] = configs[ids[i]];
      }
    }
    return EncryptionConfigService.persistMetadata(context, remaining);
  }

  static async updateDeviceKey(context: common.Context | null, serverId: string, deviceKey: string): Promise<void> {
    const configs: Record<string, EncryptionConfig> = await EncryptionConfigService.load(context);
    const config: EncryptionConfig | undefined = configs[serverId];
    if (!config || !config.enabled || config.deviceKey === deviceKey) {
      return;
    }
    config.deviceKey = deviceKey;
    await EncryptionConfigService.persistMetadata(context, configs);
  }

  private static async load(context: common.Context | null): Promise<Record<string, EncryptionConfig>> {
    const result: Record<string, EncryptionConfig> = {};
    const json: string = await PreferencesUtil.getString(context, KEY_SERVER_ENCRYPTION_CONFIGS, '{}');
    try {
      const raw = JSON.parse(json) as Record<string, Object>;
      const ids: string[] = Object.keys(raw);
      let hasLegacyKey: boolean = false;
      let migrationSucceeded: boolean = true;
      for (let i: number = 0; i < ids.length; i++) {
        const value: Object | undefined = raw[ids[i]];
        if (value && typeof value === 'object') {
          const rawConfig: Record<string, Object> = value as Record<string, Object>;
          const config: EncryptionConfig = EncryptionConfig.fromRaw(rawConfig);
          const legacyKey: Object | undefined = rawConfig['key'];
          if (typeof legacyKey === 'string' && legacyKey.length > 0) {
            hasLegacyKey = true;
            config.key = legacyKey;
            if (!await EncryptionKeyStoreService.put(ids[i], legacyKey)) {
              migrationSucceeded = false;
            }
          } else {
            const secureKey: string | null = await EncryptionKeyStoreService.get(ids[i]);
            config.key = secureKey ?? '';
          }
          result[ids[i]] = config;
        }
      }
      // 仅当所有旧 Key 都已安全写入后，才重写 Preferences 清除其中的明文 Key。
      if (hasLegacyKey && migrationSucceeded) {
        await EncryptionConfigService.persistMetadata(context, result);
      }
    } catch (_err) {
      // 配置损坏时按空配置处理，避免影响未加密消息的正常使用。
    }
    return result;
  }

  private static async persistMetadata(context: common.Context | null,
    configs: Record<string, EncryptionConfig>): Promise<boolean> {
    const stored: Record<string, StoredEncryptionConfig> = {};
    const ids: string[] = Object.keys(configs);
    for (let i: number = 0; i < ids.length; i++) {
      const config: EncryptionConfig = configs[ids[i]];
      const value = new StoredEncryptionConfig();
      value.enabled = config.enabled;
      value.algorithm = config.algorithm;
      value.mode = config.mode;
      value.padding = config.mode === 'GCM' ? 'NoPadding' : 'PKCS7';
      value.deviceKey = config.deviceKey;
      stored[ids[i]] = value;
    }
    return PreferencesUtil.putString(context, KEY_SERVER_ENCRYPTION_CONFIGS, JSON.stringify(stored));
  }
}
