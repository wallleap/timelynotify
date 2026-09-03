/**
 * 沉浸光感兼容工具
 *
 * 核心思路：
 *   运行时通过 deviceInfo.sdkApiVersion 检测系统 API 版本，
 *   API 26+ → uiMaterial.ImmersiveMaterial + systemMaterial（沉浸光感材质）
 *   API 10+ → backgroundBlurStyle（毛玻璃模糊）降级
 *
 * ⚠️ 兼容性关键点：uiMaterial 模块起始版本为 API 26，API 23 设备上不存在。
 *    若顶层静态 import，模块加载阶段即崩溃（运行时 if 分支守卫无法生效）。
 *    因此本文件通过动态 import（常量表达式）懒加载该模块：
 *    - API 26+：加载成功缓存模块命名空间，并写入 AppStorage 就绪信号
 *    - API 23-：import 返回 rejected Promise，catch 后静默走 blur 降级
 *    页面通过 @StorageProp('immersiveMaterialReady') 订阅就绪信号，
 *    就绪后调用 getSystemMaterial() 获取材质实例，否则渲染 blur 分支。
 */

import { deviceInfo } from '@kit.BasicServicesKit';
// 仅类型导入（import type）：编译期擦除，运行时不会加载 uiMaterial 模块
import type uiMaterial from '@ohos.arkui.uiMaterial';

/**
 * AppStorage 键：状态栏高度（vp）
 * EntryAbility 在开启沉浸式布局后写入实际高度，页面通过 @StorageProp('statusBarHeight') 读取
 * 注意：@StorageProp 装饰器参数需字符串字面量，页面侧直接写同名字符串
 */
export const KEY_STATUS_BAR_HEIGHT: string = 'statusBarHeight';

/** AppStorage 键：底部导航条高度（vp） */
export const KEY_NAV_BAR_HEIGHT: string = 'navBarHeight';

/** AppStorage 键：uiMaterial 模块就绪信号（API 26+ 动态加载成功后置 true） */
export const KEY_MATERIAL_READY: string = 'immersiveMaterialReady';

/**
 * AppStorage 键：沉浸光感用户开关（API 26+ 生效）。
 * 默认 true（开启）；用户在 MineView「外观」板块可关闭，关闭后所有页面走 blur 降级分支。
 * EntryAbility.onCreate 读取 Preferences 写入此键；Toggle 切换经弹窗确认重启应用后生效。
 */
export const KEY_IMMERSIVE_LIGHT_ENABLED: string = 'immersiveLightEnabled';

/** 当前设备 SDK API 版本（缓存） */
export const CURRENT_SDK_VERSION: number = deviceInfo.sdkApiVersion;

/** 判断是否支持 ImmersiveMaterial（API 26+） */
export const SUPPORTS_IMMERSIVE_MATERIAL: boolean = CURRENT_SDK_VERSION >= 26;

/** 判断是否支持 backgroundBlurStyle（API 10+） */
export const SUPPORTS_BACKGROUND_BLUR: boolean = CURRENT_SDK_VERSION >= 10;

/** 预创建的材质实例缓存（surface → Material），动态 import 成功并校验通过后填充 */
const materialCache: Record<string, uiMaterial.Material> = {};

/**
 * 异步动态加载 uiMaterial 模块（幂等，可重复调用）。
 * API 26+：加载成功并完成结构校验/实例预创建后写入 AppStorage 就绪信号；
 * API 23-：模块不存在，reject 被捕获，静默走 backgroundBlurStyle 降级分支。
 * ⚠️ 全路径防御：结构异常/实例创建失败均不写就绪信号，页面继续走 blur 分支，保证不闪退。
 * 建议 EntryAbility.onCreate 中调用一次（无需 await）。
 */
export function ensureImmersiveMaterial(): Promise<void> {
  if (!SUPPORTS_IMMERSIVE_MATERIAL) {
    return Promise.resolve();
  }
  return import('@ohos.arkui.uiMaterial').then((ns: ESObject) => {
    // 兼容两种导出结构：系统模块将整个命名空间作为 default 导出（静态 import uiMaterial from ... 的对象），
    // 动态 import 返回的命名空间中成员挂在 ns.default 下，取不到再回退 ns 本身
    const mod: ESObject = (ns as ESObject).default ?? ns;
    // 结构校验：确认 ImmersiveMaterial 构造器与 ImmersiveStyle 枚举真实存在
    if (mod && typeof mod.ImmersiveMaterial === 'function' && mod.ImmersiveStyle) {
      try {
        // 预创建各表面材质实例（材质配置对象不可变，可安全复用）
        materialCache['bar'] = new mod.ImmersiveMaterial({ style: mod.ImmersiveStyle.THIN });
        materialCache['body'] = new mod.ImmersiveMaterial({ style: mod.ImmersiveStyle.REGULAR });
        materialCache['card'] = new mod.ImmersiveMaterial({ style: mod.ImmersiveStyle.THIN });
        materialCache['toast'] = new mod.ImmersiveMaterial({ style: mod.ImmersiveStyle.THICK });
        // 缓存填充完成后才写就绪信号，保证渲染路径读缓存永不抛错
        AppStorage.setOrCreate(KEY_MATERIAL_READY, true);
      } catch (err) {
        console.warn(`[ImmersiveUtil] ImmersiveMaterial 实例创建失败，降级 blur: ${JSON.stringify(err)}`);
      }
    } else {
      console.warn('[ImmersiveUtil] uiMaterial 模块结构异常（未找到 ImmersiveMaterial），降级 blur');
    }
  }).catch((err: ESObject) => {
    // 模块不存在（API 23 及以下设备）或加载异常：静默降级为 blur 分支
    console.warn(`[ImmersiveUtil] uiMaterial 模块加载失败，降级 backgroundBlurStyle: ${JSON.stringify(err)}`);
  });
}

/**
 * 获取沉浸光感材质实例，用于 systemMaterial 属性。
 * 必须在 AppStorage 'immersiveMaterialReady' 为 true（模块已加载并预创建实例）后调用，
 * 内部为纯缓存读取，不会抛错。
 */
export function getSystemMaterial(surface: 'bar' | 'body' | 'card' | 'toast'): uiMaterial.Material {
  return materialCache[surface] as uiMaterial.Material;
}

/** 表面类型 → BlurStyle 映射（用于 backgroundBlurStyle 降级分支） */
const BLUR_STYLE_MAP: Record<string, BlurStyle> = {
  'bar': BlurStyle.Thin,
  'body': BlurStyle.Regular,
  'card': BlurStyle.Thin,
};

/**
 * 返回对应的 BlurStyle，用于 backgroundBlurStyle 降级。
 * API 10+ 返回有效值，更低版本返回 undefined（纯色回退）。
 */
export function resolveBlurStyle(surface: 'bar' | 'body' | 'card'): BlurStyle | undefined {
  if (SUPPORTS_BACKGROUND_BLUR) {
    return BLUR_STYLE_MAP[surface] ?? BlurStyle.Regular;
  }
  return undefined;
}
