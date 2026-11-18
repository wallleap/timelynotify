import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'JwsUtil';

/**
 * JWS（JSON Web Signature）载荷解码工具。
 * 华为 IAP Kit 返回的 jwsPurchaseOrder 格式为 header.payload.signature，
 * 这里仅解析 payload 读取订单字段；捐赠不发放权益，纯客户端场景不做签名验签。
 */
export class JwsUtil {
  /** 解码 JWS payload 并返回 JSON 字符串；格式错误或解码失败返回空字符串。 */
  static decodePayload(jws: string): string {
    const parts: string[] = jws.split('.');
    if (parts.length < 2) {
      return '';
    }
    return JwsUtil.base64UrlDecodeToString(parts[1]);
  }

  /** Base64URL 解码为 UTF-8 字符串，自动补齐 padding。 */
  private static base64UrlDecodeToString(input: string): string {
    try {
      let padded: string = input;
      const mod: number = padded.length % 4;
      if (mod > 0) {
        padded += '='.repeat(4 - mod);
      }
      const bytes: Uint8Array = new util.Base64Helper().decodeSync(padded, util.Type.BASIC_URL_SAFE);
      return util.TextDecoder.create('utf-8').decodeToString(bytes);
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'Base64URL 解码失败：%{public}s', msg);
      return '';
    }
  }
}
