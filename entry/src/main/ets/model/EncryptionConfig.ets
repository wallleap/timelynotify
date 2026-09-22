// 单个服务器的端到端加密配置。密钥只保存在客户端本地，不进入 ServerEntry。
export class EncryptionConfig extends Object {
  enabled: boolean = false;
  algorithm: string = 'AES128';
  mode: string = 'CBC';
  padding: string = 'PKCS7';
  key: string = '';
  // 保存配置时记录该服务器当前 device_key，供系统推送按设备定位配置。
  deviceKey: string = '';

  static fromRaw(raw: Record<string, Object>): EncryptionConfig {
    const config = new EncryptionConfig();
    config.enabled = raw['enabled'] === true;
    config.algorithm = typeof raw['algorithm'] === 'string' ? raw['algorithm'] as string : 'AES128';
    config.mode = typeof raw['mode'] === 'string' ? raw['mode'] as string : 'CBC';
    // Padding 是模式约定，不允许单独配置；读取旧配置时也统一归一化。
    config.padding = config.mode === 'GCM' ? 'NoPadding' : 'PKCS7';
    config.key = typeof raw['key'] === 'string' ? raw['key'] as string : '';
    config.deviceKey = typeof raw['deviceKey'] === 'string' ? raw['deviceKey'] as string : '';
    return config;
  }
}
