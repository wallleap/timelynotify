/**
 * 沉浸光感兼容工具
 *
 * 核心思路：
 *   运行时通过 deviceInfo.sdkApiVersion 检测系统 API 版本，
 *   API 26+ → ImmersiveMaterial / systemMaterial（起始 263）
 *   API 10+ → backgroundBlurStyle（起始 106）
 *
 * 当前编译目标 API 23，backgroundBlurStyle 已可用，优先使用。
 * 待升级至 API 26 后可在此统一切换分支。
 */

import { deviceInfo } from '@kit.BasicServicesKit';

/** 当前设备 SDK API 版本（缓存） */
export const CURRENT_SDK_VERSION: number = deviceInfo.sdkApiVersion;

/** 判断是否支持 ImmersiveMaterial（API 26+） */
export const SUPPORTS_IMMERSIVE_MATERIAL: boolean = CURRENT_SDK_VERSION >= 26;

/** 判断是否支持 backgroundBlurStyle（API 10+） */
export const SUPPORTS_BACKGROUND_BLUR: boolean = CURRENT_SDK_VERSION >= 10;

/**
 * 根据当前 API 版本返回适用的 BlurStyle。
 * - API 26+：返回 undefined，后续接入 ImmersiveMaterial/systemMaterial
 * - API 10+：返回对应的 BlurStyle
 * - 更低版本：返回 undefined（使用纯色回退）
 */
export function resolveBlurStyle(surface: 'bar' | 'body' | 'card'): BlurStyle | undefined {
  if (SUPPORTS_IMMERSIVE_MATERIAL) {
    // TODO: API 26+ 切换为 ImmersiveMaterial / systemMaterial
    return undefined;
  }
  if (SUPPORTS_BACKGROUND_BLUR) {
    switch (surface) {
      case 'bar':
        return BlurStyle.Thin;
      case 'body':
        return BlurStyle.Regular;
      case 'card':
        return BlurStyle.Thin;
      default:
        return BlurStyle.Regular;
    }
  }
  return undefined;
}
