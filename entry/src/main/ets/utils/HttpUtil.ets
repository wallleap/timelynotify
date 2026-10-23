import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'HttpUtil';

export class HttpResponse<T extends Object> {
  code: number = 0;
  result: T | null = null;
  message: string = '';
  // HTTP code=0 时保留系统网络错误码，供页面诊断；不包含 URL、鉴权或响应正文。
  networkErrorCode: number = 0;
  elapsedMs: number = 0;
}

/** 将系统连接错误转换为可展示的安全文案，未知错误仍保留数字码供设备间比对。 */
export function formatNetworkFailure(code: number): string {
  let message: string = '无法连接到服务器，请稍后重试';
  if (code === 2300005 || code === 2300006) {
    message = '服务器域名解析失败，请稍后重试';
  } else if (code === 2300007) {
    message = '无法建立服务器连接，请稍后重试';
  } else if (code === 2300028) {
    message = '服务器请求超时，请重试';
  } else if (code === 2300058 || code === 2300059 || code === 2300060) {
    message = '服务器安全连接校验失败，请检查证书与设备时间';
  } else if (code === 2300016) {
    message = '服务器 HTTP/2 连接异常，请重试';
  }
  return code > 0 ? `${message}（错误码 ${code}）` : message;
}

/** 总时限使用与系统超时一致的错误码，不能依赖原生请求一定会自行结束。 */
class HttpDeadlineError extends Error {
  code: number = 2300028;
}

/** BusinessError 可能继承 Error，必须先取 code，不能只取 Error.message。 */
function networkErrorCode(err: Object): number {
  if (err && typeof err === 'object') {
    const value: Object = (err as Record<string, Object>)['code'];
    const code: number = typeof value === 'number' ? value : Number(value);
    return Number.isFinite(code) && code > 0 ? code : 0;
  }
  return 0;
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

  // 第一个参数传入完整 URL（由上层 ServerManager.resolveURL 拼接好 baseURL + path）
  static async post<T extends Object, B extends Object>(
    fullURL: string,
    body: B,
    headers?: Record<string, string>
  ): Promise<HttpResponse<T>> {
    return HttpUtil.request<T>(fullURL, http.RequestMethod.POST, headers, JSON.stringify(body));
  }

  // GET 请求（无 body）；默认总时限 10s，显式放宽读超时也同步放宽总时限。
  static async get<T extends Object>(
    fullURL: string,
    headers?: Record<string, string>,
    readTimeoutMs: number = HttpUtil.TIMEOUT_MS
  ): Promise<HttpResponse<T>> {
    return HttpUtil.request<T>(fullURL, http.RequestMethod.GET, headers, undefined, readTimeoutMs);
  }

  // DELETE 请求（无 body）
  static async delete<T extends Object>(
    fullURL: string,
    headers?: Record<string, string>
  ): Promise<HttpResponse<T>> {
    return HttpUtil.request<T>(fullURL, http.RequestMethod.DELETE, headers, undefined);
  }

  private static async request<T extends Object>(
    fullURL: string,
    method: http.RequestMethod,
    headers?: Record<string, string>,
    body?: string,
    readTimeoutMs: number = HttpUtil.TIMEOUT_MS
  ): Promise<HttpResponse<T>> {
    const httpRequest = http.createHttp();
    const url: string = fullURL;
    const result = new HttpResponse<T>();
    const startedAt: number = Date.now();
    let deadlineTimer: number = -1;
    let destroyed: boolean = false;
    // 超时与 finally 共用一次释放，避免取消回调触发后重复销毁原生对象。
    const destroyRequest = (): void => {
      if (destroyed) return;
      destroyed = true;
      try {
        httpRequest.destroy();
      } catch (_err) {
        hilog.warn(DOMAIN, TAG, 'HTTP 请求资源释放失败');
      }
    };

    const mergedHeaders: Record<string, string> = {};
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

    const options: http.HttpRequestOptions = {
      method: method,
      header: mergedHeaders,
      connectTimeout: HttpUtil.TIMEOUT_MS,
      readTimeout: readTimeoutMs,
    };
    if (body !== undefined && body !== null) {
      mergedHeaders['Content-Type'] = 'application/json';
      options.extraData = body;
    }

    try {
      const totalTimeoutMs: number = Math.max(HttpUtil.TIMEOUT_MS, readTimeoutMs);
      const deadline: Promise<http.HttpResponse> = new Promise<http.HttpResponse>((_resolve, reject) => {
        deadlineTimer = setTimeout(() => {
          // 先结束等待再中止原生请求，取消产生的异常由 race 同时接管。
          reject(new HttpDeadlineError('HTTP request deadline exceeded'));
          destroyRequest();
        }, totalTimeoutMs);
      });
      const response: http.HttpResponse = await Promise.race([httpRequest.request(url, options), deadline]);

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
      result.code = 0;
      result.networkErrorCode = networkErrorCode(err);
      result.message = formatNetworkFailure(result.networkErrorCode);
      // 不记录请求 URL/路径、Header、Token 或原始错误文本，避免 SDK 回显敏感参数。
      hilog.error(DOMAIN, TAG, 'HTTP 连接失败：code=%{public}d elapsedMs=%{public}d',
        result.networkErrorCode, Date.now() - startedAt);
    } finally {
      if (deadlineTimer >= 0) clearTimeout(deadlineTimer);
      result.elapsedMs = Date.now() - startedAt;
      destroyRequest();
    }
    return result;
  }
}
