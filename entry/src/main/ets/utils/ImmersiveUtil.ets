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

/** AppStorage 键：uiMaterial 模块就绪信号（API 26+ 动态加载成功且设备支持材质后置 true） */
export const KEY_MATERIAL_READY: string = 'immersiveMaterialReady';

/**
 * AppStorage 键：uiMaterial 模块已加载、材质实例已预创建（不要求设备 supported）。
 * supported=false 的设备 systemMaterial 虽 no-op，但半透明内容/容器仍需走「材质样式分支」
 * （透明 List + glass 卡片 + 按钮 backgroundColor 兜底），因此与 READY 分开。
 */
export const KEY_MATERIAL_LOADED: string = 'immersiveMaterialLoaded';

/**
 * AppStorage 键：当前设备硬件是否支持沉浸材质（isImmersiveMaterialSupported）。
 * 低算力设备/部分模拟器为 false：systemMaterial 可设置但不生效，入口行也不展示。
 * ensureImmersiveMaterial 完成探测后写入；API 26 以下直接为 false。
 */
export const KEY_MATERIAL_SUPPORTED: string = 'immersiveMaterialSupported';

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
    AppStorage.setOrCreate(KEY_MATERIAL_SUPPORTED, false);
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
        // 浮动操作按钮：官方「纯色 + 质感」组合——
        // materialColor 用不透明控件纯色（color_bg_action，亮浅灰/暗深灰蓝，随主题切换），
        // 提供在卡片上清晰可辨的背板；不透明色会遮住材质滤镜（无模糊透出），
        // 但保留质感部分：交互形变 + 点光源 + 默认阴影。
        // 不要用 backgroundColor 叠色（材质生效时会被还原为透明，且会覆盖光感）。
        const actionLightEffect: uiMaterial.LightEffectOptions = {};
        materialCache['action'] = new mod.ImmersiveMaterial({
          style: mod.ImmersiveStyle.REGULAR,
          materialColor: $r('app.color.color_bg_action'),
          interactive: true,
          lightEffect: actionLightEffect
        });
        // 详情 Sheet 面积较大且卡片保持实色，薄材质才能让下层页面明显透出。
        materialCache['sheet'] = new mod.ImmersiveMaterial({ style: mod.ImmersiveStyle.THIN });
        materialCache['toast'] = new mod.ImmersiveMaterial({ style: mod.ImmersiveStyle.THICK });
        // 弹窗（CustomDialog/系统对话框）：官方弹窗类默认样式为 ULTRA_THICK，
        // 厚材质弱化下层干扰、保证表单与长文本可读性；枚举缺失时回退 THICK。
        const dialogStyle: number = mod.ImmersiveStyle.ULTRA_THICK ?? mod.ImmersiveStyle.THICK;
        materialCache['dialog'] = new mod.ImmersiveMaterial({ style: dialogStyle });
        // 设备能力闸门：部分设备（典型为 SMOOTH 低算力模拟器）isImmersiveMaterialSupported=false，
        // 官方明确此时 systemMaterial「can be set but has no effect」。不写就绪信号，
        // 全应用（弹窗/标题栏/按钮/Toast 等）统一走纯色/模糊降级，避免内容透明却露出系统白底。
        let supported: boolean = true;
        let level: number = -1;
        try {
          if (typeof mod.isImmersiveMaterialSupported === 'function') {
            supported = mod.isImmersiveMaterialSupported();
          }
          if (typeof mod.getGlobalMaterialLevel === 'function') {
            level = mod.getGlobalMaterialLevel();
          }
        } catch (e) {
          console.warn(`[ImmersiveUtil] 材质能力查询失败，按支持处理: ${JSON.stringify(e)}`);
        }
        console.info(`[ImmersiveUtil] materialLevel=${level} supported=${supported} sdk=${CURRENT_SDK_VERSION}`);
        AppStorage.setOrCreate(KEY_MATERIAL_SUPPORTED, supported);
        // 实例已全部预创建：即使设备不支持（systemMaterial no-op），内容层也可走材质样式分支
        // （透明底 + glass 色 + backgroundColor 兜底），故 LOADED 先于 supported 闸门写入。
        AppStorage.setOrCreate(KEY_MATERIAL_LOADED, true);
        if (!supported) {
          return;
        }
        // 缓存填充完成且设备支持后才写就绪信号，保证渲染路径读缓存永不抛错
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
export function getSystemMaterial(surface: 'bar' | 'body' | 'card' | 'action' | 'sheet' | 'toast' | 'dialog'): uiMaterial.Material {
  return materialCache[surface] as uiMaterial.Material;
}

/**
 * 沉浸材质当前是否处于生效态：API 26+ 且用户开关未关闭且模块已动态加载就绪。
 * 供弹窗等场景判断「走材质背板」还是「纯色/模糊降级」。
 */
export function isImmersiveMaterialActive(): boolean {
  return SUPPORTS_IMMERSIVE_MATERIAL
    && AppStorage.get<boolean>(KEY_IMMERSIVE_LIGHT_ENABLED) !== false
    && AppStorage.get<boolean>(KEY_MATERIAL_READY) === true;
}

/**
 * uiMaterial 模块已加载且用户开关开启（不要求设备 supported）。
 * 用于「材质样式分支」：systemMaterial 调用本身在不支持设备上安全（no-op），
 * 配套半透明色/backgroundColor 兜底即可，半模态内容层据此保持通透。
 */
export function isImmersiveMaterialLoaded(): boolean {
  return SUPPORTS_IMMERSIVE_MATERIAL
    && AppStorage.get<boolean>(KEY_IMMERSIVE_LIGHT_ENABLED) !== false
    && AppStorage.get<boolean>(KEY_MATERIAL_LOADED) === true;
}

/**
 * 弹窗专用：材质生效时返回 dialog 材质（挂到 CustomDialogControllerOptions /
 * promptAction.showDialog 等 options 的 systemMaterial 字段），否则返回 undefined
 * （字段缺省即系统纯色弹窗）。可在组件字段初始化期安全调用：未就绪时返回 undefined。
 */
export function getDialogMaterial(): uiMaterial.Material | undefined {
  return isImmersiveMaterialActive() ? materialCache['dialog'] as uiMaterial.Material : undefined;
}

/**
 * 自定义弹窗（@CustomDialog）背板配置：取出返回值的三个字段分别赋给
 * CustomDialogControllerOptions 的同名字段（ArkTS 禁用对象展开，不能 ...spread）。
 *
 * 关键：模糊必须挂在 controller options（系统 dialog 容器，与 bindSheet/promptAction 同渲染路径）
 * 上，低算力设备/模拟器才有真实高斯模糊；挂在 @CustomDialog 内容根节点上无效——
 * dialog 内容子树采样不到下层页面，只会看到 BlurStyle 自带的不透明 tint 白底。
 *
 * - 沉浸材质生效：ULTRA_THICK 材质背板 + 内容透明
 * - 降级（旧系统/低算力/模拟器/开关关）：系统容器 COMPONENT_THICK 模糊 + 80% 弹窗底色保证可读性
 */
export interface DialogBackgroundOptions {
  systemMaterial: uiMaterial.Material | undefined;
  backgroundColor: ResourceColor;
  backgroundBlurStyle: BlurStyle | undefined;
}

export function getDialogBackgroundOptions(): DialogBackgroundOptions {
  if (isImmersiveMaterialActive()) {
    return {
      systemMaterial: materialCache['dialog'] as uiMaterial.Material,
      backgroundColor: Color.Transparent,
      backgroundBlurStyle: undefined,
    };
  }
  return {
    systemMaterial: undefined,
    backgroundColor: $r('app.color.color_bg_dialog_glass'),
    backgroundBlurStyle: BlurStyle.COMPONENT_THICK,
  };
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
