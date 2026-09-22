import { asset } from '@kit.AssetStoreKit';
import { BusinessError, SuppressWarnings, SuppressWarningsType } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'EncryptionKeyStore';
const ALIAS_PREFIX: string = 'timelynotify.encryption.';
const ERROR_NOT_FOUND: number = 24000002;

// Asset Store 的 SysCap 在 HarmonyOS phone-hmos 描述中未列出，但运行时会先用 canIUse 检查。
// 注解只抑制这一个类中已完成兼容处理的静态多设备告警。
@SuppressWarnings({ rules: [SuppressWarningsType.SYSCAP] })
export class EncryptionKeyStoreService {
  static async get(serverId: string): Promise<string | null> {
    if (!EncryptionKeyStoreService.isAvailable()) {
      return null;
    }
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, EncryptionKeyStoreService.encodeAlias(serverId));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const results: asset.AssetMap[] = await asset.query(query);
      if (results.length === 0) {
        return '';
      }
      const secret: asset.Value | undefined = results[0].get(asset.Tag.SECRET);
      if (!(secret instanceof Uint8Array)) {
        hilog.warn(DOMAIN, TAG, '安全存储返回的 Key 格式无效：serverId=%{public}s', serverId);
        return null;
      }
      return util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true }).decodeToString(secret);
    } catch (err) {
      if (EncryptionKeyStoreService.errorCode(err) === ERROR_NOT_FOUND) {
        return '';
      }
      EncryptionKeyStoreService.logFailure('读取', serverId, err);
      return null;
    }
  }

  static async put(serverId: string, key: string): Promise<boolean> {
    if (!EncryptionKeyStoreService.isAvailable() || key.length === 0) {
      return false;
    }
    const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, EncryptionKeyStoreService.encodeAlias(serverId));
    attributes.set(asset.Tag.SECRET, util.TextEncoder.create('utf-8').encodeInto(key));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    try {
      await asset.add(attributes);
      return true;
    } catch (err) {
      EncryptionKeyStoreService.logFailure('写入', serverId, err);
      return false;
    }
  }

  static async remove(serverId: string): Promise<boolean> {
    if (!EncryptionKeyStoreService.isAvailable()) {
      return false;
    }
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, EncryptionKeyStoreService.encodeAlias(serverId));
    try {
      await asset.remove(query);
      return true;
    } catch (err) {
      if (EncryptionKeyStoreService.errorCode(err) === ERROR_NOT_FOUND) {
        return true;
      }
      EncryptionKeyStoreService.logFailure('删除', serverId, err);
      return false;
    }
  }

  private static isAvailable(): boolean {
    if (canIUse('SystemCapability.Security.Asset')) {
      return true;
    }
    hilog.error(DOMAIN, TAG, '当前设备不支持 Asset Store，无法安全保存端到端加密 Key');
    return false;
  }

  private static encodeAlias(serverId: string): Uint8Array {
    return util.TextEncoder.create('utf-8').encodeInto(`${ALIAS_PREFIX}${serverId}`);
  }

  private static errorCode(err: Object): number {
    const businessError: BusinessError = err as BusinessError;
    return typeof businessError.code === 'number' ? businessError.code : 0;
  }

  private static logFailure(operation: string, serverId: string, err: Object): void {
    const message: string = err instanceof Error ? err.message : String(err);
    hilog.error(DOMAIN, TAG, '%{public}s Key 失败：serverId=%{public}s code=%{public}d message=%{public}s',
      operation, serverId, EncryptionKeyStoreService.errorCode(err), message);
  }
}
