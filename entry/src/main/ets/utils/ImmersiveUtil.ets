/**
 * 沉浸式布局工具
 *
 * 提供状态栏/导航条高度的 AppStorage 键名，以及毛玻璃模糊样式解析。
 * 历史说明：曾支持 API 26+ uiMaterial.ImmersiveMaterial 沉浸光感材质
 * （systemMaterial），因 AGC 拒绝 beta API（26.0.0 为 Developer Preview）
 * 已整体移除，统一使用 backgroundBlurStyle 毛玻璃降级方案。
 * 如需恢复该方案，可检出 git tag `api26-beta-material`。
 */

import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * AppStorage 键：状态栏高度（vp）
 * EntryAbility 在开启沉浸式布局后写入实际高度，页面通过 @StorageProp('statusBarHeight') 读取
 * 注意：@StorageProp 装饰器参数需字符串字面量，页面侧直接写同名字符串
 */
export const KEY_STATUS_BAR_HEIGHT: string = 'statusBarHeight';

/** AppStorage 键：底部导航条高度（vp） */
export const KEY_NAV_BAR_HEIGHT: string = 'navBarHeight';

/** 当前设备 SDK API 版本（缓存） */
export const CURRENT_SDK_VERSION: number = deviceInfo.sdkApiVersion;

/** 判断是否支持 backgroundBlurStyle（API 10+） */
export const SUPPORTS_BACKGROUND_BLUR: boolean = CURRENT_SDK_VERSION >= 10;

/** 表面类型 → BlurStyle 映射（用于 backgroundBlurStyle） */
const BLUR_STYLE_MAP: Record<string, BlurStyle> = {
  'bar': BlurStyle.Thin,
  'body': BlurStyle.Regular,
  'card': BlurStyle.Thin,
};

/**
 * 返回对应的 BlurStyle，用于 backgroundBlurStyle。
 * API 10+ 返回有效值，更低版本返回 undefined（纯色回退）。
 */
export function resolveBlurStyle(surface: 'bar' | 'body' | 'card'): BlurStyle | undefined {
  if (SUPPORTS_BACKGROUND_BLUR) {
    return BLUR_STYLE_MAP[surface] ?? BlurStyle.Regular;
  }
  return undefined;
}
