import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import showToast from '../components/showToast';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'ExternalLinkSvc';

/** 使用文档地址（MineView 顶部常量搬入服务层） */
export const USE_DOCS_URL: string = 'https://docs.timelynotify.oicode.cn';

/** 隐私协议地址（MineView 顶部常量搬入服务层） */
export const PRIVACY_URL: string =
  'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2026233837759005504';

/**
 * 外部链接跳转服务：统一封装 SharePage 内嵌 WebView 的路由跳转。
 * 失败时弹 Toast 提示「无法打开页面」。
 */
export class ExternalLinkService {
  /**
   * 通过 SharePage 打开外部 URL。
   * @param uiCtx 调用方 UIContext
   * @param url 目标 URL
   * @param title 顶栏标题
   */
  static async openSharePage(uiCtx: UIContext, url: string, title: string): Promise<void> {
    try {
      await uiCtx.getRouter().pushUrl({
        url: 'pages/SharePage', params: { url, title }
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '跳转 SharePage 失败：%{public}s', msg);
      showToast(uiCtx, '无法打开页面');
    }
  }
}
