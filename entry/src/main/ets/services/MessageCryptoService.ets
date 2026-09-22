import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { EncryptionConfig } from '../model/EncryptionConfig';
import { EncryptionConfigService } from './EncryptionConfigService';

export class MessageCryptoService {
  static async decrypt(config: EncryptionConfig, ciphertextBase64: string,
    ivText: string): Promise<Record<string, Object>> {
    const validation: string = EncryptionConfigService.validate(config);
    if (validation.length > 0) {
      throw new Error(validation);
    }
    if (!canIUse('SystemCapability.Security.CryptoFramework.Key.SymKey') ||
      !canIUse('SystemCapability.Security.CryptoFramework.Cipher')) {
      throw new Error('当前设备不支持端到端解密所需的加密能力');
    }
    try {
      const keyBytes: Uint8Array = util.TextEncoder.create('utf-8').encodeInto(config.key);
      // @SuppressWarnings syscap
      const keyGenerator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator(config.algorithm);
      const key: cryptoFramework.SymKey = keyGenerator.convertKeySync({ data: keyBytes });
      const transformation: string = config.mode === 'GCM' ?
        `${config.algorithm}|GCM` : `${config.algorithm}|${config.mode}|${config.padding}`;
      // @SuppressWarnings syscap
      const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher(transformation);
      const decoded: Uint8Array = new util.Base64Helper().decodeSync(ciphertextBase64);

      if (config.mode === 'ECB') {
        // @SuppressWarnings syscap
        await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, null);
        // @SuppressWarnings syscap
        return MessageCryptoService.decodeJson((await cipher.doFinal({ data: decoded })).data);
      }

      const iv: Uint8Array = util.TextEncoder.create('utf-8').encodeInto(ivText);
      if (config.mode === 'CBC') {
        if (iv.length !== 16) {
          throw new Error('CBC IV 必须为 16 个 UTF-8 字节');
        }
        const params: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: { data: iv } };
        // @SuppressWarnings syscap
        await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, params);
        // @SuppressWarnings syscap
        return MessageCryptoService.decodeJson((await cipher.doFinal({ data: decoded })).data);
      }

      if (iv.length !== 12) {
        throw new Error('GCM IV 必须为 12 个 UTF-8 字节');
      }
      if (decoded.length <= 16) {
        throw new Error('GCM 密文缺少认证标签');
      }
      const encrypted: Uint8Array = decoded.slice(0, decoded.length - 16);
      const authTag: Uint8Array = decoded.slice(decoded.length - 16);
      const params: cryptoFramework.GcmParamsSpec = {
        algName: 'GcmParamsSpec',
        iv: { data: iv },
        aad: { data: new Uint8Array() },
        authTag: { data: authTag },
      };
      // @SuppressWarnings syscap
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, params);
      // @SuppressWarnings syscap
      return MessageCryptoService.decodeJson((await cipher.doFinal({ data: encrypted })).data);
    } catch (err) {
      throw err instanceof Error ? err : new Error(String(err));
    }
  }

  private static decodeJson(bytes: Uint8Array): Record<string, Object> {
    const text: string = util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true }).decodeToString(bytes);
    const value: Object = JSON.parse(text) as Object;
    if (!value || typeof value !== 'object' || value instanceof Array) {
      throw new Error('解密结果不是 JSON 对象');
    }
    return value as Record<string, Object>;
  }
}
