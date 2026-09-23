import { pushCommon, RemoteNotificationExtensionAbility } from '@kit.PushKit';
import { application } from '@kit.AbilityKit';
import { EncryptionConfig } from '../model/EncryptionConfig';
import { EncryptionConfigService } from '../services/EncryptionConfigService';
import { MessageCryptoService } from '../services/MessageCryptoService';

class NotificationContent implements pushCommon.RemoteNotificationContent {
  title?: string;
  text?: string;
}

// 未来取得 push-type: 2 权益后的预留解密入口。当前服务端使用普通 push-type: 0
// 发送安全占位通知，不会进入此扩展；保留实现便于权益开通后继续联调。
// 扩展只返回替换后的通知文案，不向服务器上传配置或明文。
export default class RemoteNotificationExtAbility extends RemoteNotificationExtensionAbility {
  async onReceiveMessage(info: pushCommon.RemoteNotificationInfo): Promise<pushCommon.RemoteNotificationContent> {
    const fallback = new NotificationContent();
    fallback.title = '加密通知';
    fallback.text = '无法解密，请打开应用检查加密设置';
    try {
      const payload: Record<string, Object> = this.parsePayload(info.data);
      const deviceKey: string = this.readString(payload, 'device_key', 'deviceKey');
      const ciphertext: string = this.readString(payload, 'ciphertext');
      const iv: string = this.readString(payload, 'iv');
      if (deviceKey.length === 0 || ciphertext.length === 0) {
        return fallback;
      }
      const config: EncryptionConfig | null = await EncryptionConfigService.findByDeviceKey(
        application.getApplicationContext(), deviceKey);
      if (!config) {
        return fallback;
      }
      const clear: Record<string, Object> = await MessageCryptoService.decrypt(config, ciphertext, iv);
      const result = new NotificationContent();
      result.title = this.readString(clear, 'title');
      result.text = this.readString(clear, 'body', 'message');
      return result;
    } catch (_err) {
      // 扩展必须在十秒内返回；任何格式或认证错误都使用无敏感信息的占位内容。
      return fallback;
    }
  }

  private parsePayload(data: string): Record<string, Object> {
    const raw: Object = JSON.parse(data) as Object;
    if (!raw || typeof raw !== 'object' || raw instanceof Array) {
      throw new Error('推送数据格式错误');
    }
    const payload = raw as Record<string, Object>;
    // 兼容 Push Kit 外层 data 再包一层 JSON 字符串的格式。
    const nested: Object | undefined = payload['data'];
    if (typeof nested === 'string' && nested.length > 0 && nested[0] === '{') {
      return this.parsePayload(nested);
    }
    return payload;
  }

  private readString(raw: Record<string, Object>, first: string, second: string = ''): string {
    const firstValue: Object | undefined = raw[first];
    if (typeof firstValue === 'string') {
      return firstValue;
    }
    if (second.length > 0) {
      const secondValue: Object | undefined = raw[second];
      return typeof secondValue === 'string' ? secondValue : '';
    }
    return '';
  }
}
