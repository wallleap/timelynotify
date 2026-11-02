import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import showToast from '../components/showToast';
import { DOMAIN } from '../common/Constant';
import { LocalDocumentService } from './LocalDocumentService';

const TAG: string = 'ExternalLinkSvc';

/** 文档链接身份；匹配本站的入口统一转入本地 Markdown，不请求在线站点。 */
export const USE_DOCS_URL: string = 'https://docs.timelynotify.oicode.cn';

/** 隐私协议地址（MineView 顶部常量搬入服务层） */
export const PRIVACY_URL: string =
  'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2026233837759005504';

/**
 * 链接跳转服务：文档使用本地阅读页，其余链接沿用 SharePage。
 * 失败时弹 Toast 提示「无法打开页面」。
 */
export class ExternalLinkService {
  /**
   * 通过对应阅读页打开链接，旧文档入口无需逐一维护两套 URL。
   * @param uiCtx 调用方 UIContext
   * @param url 目标 URL
   * @param title 顶栏标题
   */
  static async openSharePage(uiCtx: UIContext, url: string, title: string): Promise<void> {
    try {
      await uiCtx.getRouter().pushUrl({
        url: LocalDocumentService.isDocumentUrl(url) ? 'pages/LocalDocumentPage' : 'pages/SharePage',
        params: { url, title }
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '打开阅读页面失败：%{public}s', msg);
      showToast(uiCtx, '无法打开页面');
    }
  }
}
