import { DOMAIN } from '../common/Constant';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 全局 Toast 封装（基于 UIContext 的 PromptAction）。
 * 历史说明：曾支持 API 26+ systemMaterial 沉浸光感材质，因 AGC 拒绝 beta API
 * 已移除，统一使用普通 Toast。
 */
export default function showToast(ctx: UIContext, message: string, durationMs: number = 1500,
  tag: string = 'Toast'): void {
  try {
    ctx.getPromptAction().showToast({ message: message, duration: durationMs });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    hilog.warn(DOMAIN, tag, 'Toast 调用失败：%{public}s', msg);
  }
}
