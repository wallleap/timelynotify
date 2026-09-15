import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'ClipboardSvc';

/**
 * 剪贴板写入服务：统一封装 pasteboard 调用与异常处理。
 * 调用方负责后续的 Toast 文案与展示时长；本服务只返回成功/失败标志。
 */
export class ClipboardService {
  /**
   * 将文本写入系统剪贴板。
   * @param text 待写入文本
   * @returns true=写入成功；false=写入失败（异常已记录日志）
   */
  static async copyText(text: string): Promise<boolean> {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const sys: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      await sys.setData(data);
      return true;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '剪贴板写入失败：%{public}s', msg);
      return false;
    }
  }
}
