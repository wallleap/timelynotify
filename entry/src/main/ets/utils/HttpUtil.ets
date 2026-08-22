import { http } from '@kit.NetworkKit';
import { ApiConfig } from '../config/ApiConfig';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'HttpUtil';

export class HttpResponse<T extends Object> {
  code: number = 0;
  result: T | null = null;
  message: string = '';
}

// 兼容 ArkTS catch 语法限制：NetworkKit 抛错通常不是 Error 子类，
// 而是带 code/message 字段的结构化对象；逐字段取以免打印成 [object Object]
function formatError(err: Object): string {
  if (err instanceof Error) {
    return err.message;
  }
  const map: Record<string, string> = {};
  if (typeof err === 'object') {
    const anyErr = err as Record<string, Object>;
    if (anyErr['code'] !== undefined && anyErr['code'] !== null) {
      map['code'] = String(anyErr['code']);
    }
    if (anyErr['message'] !== undefined && anyErr['message'] !== null) {
      map['message'] = String(anyErr['message']);
    }
    if (Object.keys(map).length === 0) {
      try {
        return JSON.stringify(err);
      } catch (_ignore) {
        return String(err);
      }
    }
    const parts: string[] = [];
    const keys: string[] = Object.keys(map);
    for (let i = 0; i < keys.length; i++) {
      parts.push(`${keys[i]}=${map[keys[i]]}`);
    }
    return parts.join(' ');
  }
  return String(err);
}

export class HttpUtil {
  private static readonly TIMEOUT_MS: number = 10000;

  static async post<T extends Object, B extends Object>(
    path: string,
    body: B,
    headers?: Record<string, string>
  ): Promise<HttpResponse<T>> {
    const httpRequest = http.createHttp();
    const url = `${ApiConfig.baseURL}${path}`;
    const result = new HttpResponse<T>();

    const mergedHeaders: Record<string, string> = {};
    mergedHeaders['Content-Type'] = 'application/json';
    mergedHeaders['Accept'] = 'application/json';
    if (headers) {
      const keys: string[] = Object.keys(headers);
      for (let i = 0; i < keys.length; i++) {
        const k: string = keys[i];
        const v: string = headers[k];
        if (v !== undefined && v !== null) {
          mergedHeaders[k] = v;
        }
      }
    }

    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: mergedHeaders,
        extraData: JSON.stringify(body),
        connectTimeout: HttpUtil.TIMEOUT_MS,
        readTimeout: HttpUtil.TIMEOUT_MS,
      });

      if (response.responseCode >= 200 && response.responseCode < 300) {
        result.code = response.responseCode;
        if (typeof response.result === 'string' && response.result.length > 0) {
          try {
            const parsed: Object = JSON.parse(response.result);
            result.result = parsed as T;
          } catch (parseErr) {
            const msg: string = formatError(parseErr);
            hilog.warn(DOMAIN, TAG, '响应体非 JSON，按原文本返回：%{public}s', msg);
          }
        }
      } else {
        result.code = response.responseCode;
        result.message = `HTTP ${response.responseCode}`;
      }
    } catch (err) {
      const msg: string = formatError(err);
      result.code = 0;
      result.message = `请求失败：${msg}`;
      hilog.error(DOMAIN, TAG, '%{public}s', result.message);
    } finally {
      httpRequest.destroy();
    }
    return result;
  }
}
