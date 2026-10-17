import { common } from '@kit.AbilityKit';
import { updateManager } from '@kit.AppGalleryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DOMAIN, KEY_APP_UPDATE_AVAILABLE } from '../common/Constant';

const TAG: string = 'AppUpdateService';
// 回前台时至多每六小时静默检测一次；手动检测和从应用市场返回不受此间隔限制。
const AUTO_CHECK_INTERVAL_MS: number = 6 * 60 * 60 * 1000;

/** 更新检测结果：失败或市场暂不可用时保持 UNKNOWN，不误报为最新版本。 */
export enum AppUpdateCheckStatus {
  UNKNOWN = 0,
  AVAILABLE = 1,
  CURRENT = 2,
}

/** 集中管理应用市场版本检测、前台节流及 Mine 页提示点状态。 */
export class AppUpdateService {
  // 仅记录本次进程中最近一次成功检测；冷启动总会重新检测。
  private static lastSuccessfulCheckAt: number = 0;
  private static lastStatus: AppUpdateCheckStatus = AppUpdateCheckStatus.UNKNOWN;
  // 多个入口同时检测时复用同一请求，避免并发调用 AppGallery Kit。
  private static inFlight: Promise<AppUpdateCheckStatus> | null = null;
  // 从本应用打开市场后，下一次回前台必须重新确认是否仍有更新。
  private static recheckAfterMarket: boolean = false;

  /** 应用进入前台后静默检测；失败仅记日志，不向用户弹窗。 */
  static onForeground(ctx: common.UIAbilityContext): void {
    const force: boolean = AppUpdateService.recheckAfterMarket;
    AppUpdateService.recheckAfterMarket = false;
    AppUpdateService.check(ctx, force).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, '前台检测更新异常：%{public}s', err.message);
    });
  }

  /** 用户主动检测时立即检查；若已有请求正在运行则等待该请求的结果。 */
  static checkManually(ctx: common.UIAbilityContext): Promise<AppUpdateCheckStatus> {
    return AppUpdateService.check(ctx, true);
  }

  /** 标记从本应用打开应用市场，返回前台时需绕过六小时间隔。 */
  static markMarketOpened(): void {
    AppUpdateService.recheckAfterMarket = true;
  }

  /** 跳转应用市场失败时撤销强制复查标记。 */
  static cancelMarketRecheck(): void {
    AppUpdateService.recheckAfterMarket = false;
  }

  /** 复用进行中的请求，并在成功检测后才开始计算下次自动检测间隔。 */
  private static async check(ctx: common.UIAbilityContext, force: boolean): Promise<AppUpdateCheckStatus> {
    if (AppUpdateService.inFlight) {
      return AppUpdateService.inFlight;
    }
    const now: number = Date.now();
    if (!force && AppUpdateService.lastSuccessfulCheckAt > 0 && now >= AppUpdateService.lastSuccessfulCheckAt &&
      now - AppUpdateService.lastSuccessfulCheckAt < AUTO_CHECK_INTERVAL_MS) {
      return AppUpdateService.lastStatus;
    }
    const request: Promise<AppUpdateCheckStatus> = AppUpdateService.performCheck(ctx);
    AppUpdateService.inFlight = request;
    try {
      return await request;
    } finally {
      AppUpdateService.inFlight = null;
    }
  }

  /** 将已确认的市场结果同步给界面；失败时保留现有提示状态并允许下次重试。 */
  private static async performCheck(ctx: common.UIAbilityContext): Promise<AppUpdateCheckStatus> {
    try {
      const result: updateManager.CheckUpdateResult = await updateManager.checkAppUpdate(ctx);
      if (result.updateAvailable === updateManager.UpdateAvailableCode.LATER_VERSION_EXIST) {
        AppUpdateService.lastStatus = AppUpdateCheckStatus.AVAILABLE;
        AppStorage.setOrCreate(KEY_APP_UPDATE_AVAILABLE, true);
      } else if (result.updateAvailable === updateManager.UpdateAvailableCode.LATER_VERSION_NOT_EXIST) {
        AppUpdateService.lastStatus = AppUpdateCheckStatus.CURRENT;
        AppStorage.setOrCreate(KEY_APP_UPDATE_AVAILABLE, false);
      } else {
        hilog.warn(DOMAIN, TAG, '应用市场返回未识别的更新状态');
        return AppUpdateCheckStatus.UNKNOWN;
      }
      AppUpdateService.lastSuccessfulCheckAt = Date.now();
      return AppUpdateService.lastStatus;
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '检测更新失败：%{public}s', msg);
      return AppUpdateCheckStatus.UNKNOWN;
    }
  }
}
