import { DOMAIN } from '../common/Constant';
import { getSystemMaterial, isImmersiveMaterialActive } from '../utils/ImmersiveUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 全局 Toast 封装（基于 UIContext 的 PromptAction）。
 * API 26+ 且 uiMaterial 模块动态加载就绪时，附带沉浸光感材质；否则普通 Toast。
 * 注意：不在此处顶层静态导入 uiMaterial，避免 API 23 设备模块加载崩溃。
 */
export default function showToast(ctx: UIContext, message: string, durationMs: number = 1500,
  tag: string = 'Toast'): void {
  try {
    const materialReady: boolean = isImmersiveMaterialActive();
    if (materialReady) {
      ctx.getPromptAction().showToast({
        message: message,
        duration: durationMs,
        systemMaterial: getSystemMaterial('toast')
      });
    } else {
      ctx.getPromptAction().showToast({ message: message, duration: durationMs });
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    hilog.warn(DOMAIN, tag, 'Toast 调用失败：%{public}s', msg);
  }
}
