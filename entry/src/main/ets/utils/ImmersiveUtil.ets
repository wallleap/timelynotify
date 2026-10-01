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
 *    - API 26+：加载成功预创建材质实例，并写入 AppStorage 加载信号
 *    - API 23-：import 返回 rejected Promise，catch 后静默走 blur 降级
 *    页面通过 @StorageProp('immersiveMaterialLoaded') 订阅加载信号；
 *    API、用户开关与材质可用性统一由本工具判断。
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

/**
 * AppStorage 键：uiMaterial 模块已加载、材质实例已预创建。
 * 仅表示实例可用；设备支持程度由系统处理，不参与组件分支判断。
 */
export const KEY_MATERIAL_LOADED: string = 'immersiveMaterialLoaded';

/**
 * AppStorage 键：沉浸光感用户开关（API 26+ 生效）。
 * 默认 true（开启）；用户在 MineView「外观」板块可关闭，关闭后所有页面走 blur 降级分支。
 * EntryAbility.onCreate 读取 Preferences 写入此键；Toggle 切换经弹窗确认重启应用后生效。
 */
export const KEY_IMMERSIVE_LIGHT_ENABLED: string = 'immersiveLightEnabled';

/** 当前设备 SDK API 版本（缓存） */
const CURRENT_SDK_VERSION: number = deviceInfo.sdkApiVersion;

/** 判断是否支持 ImmersiveMaterial（API 26+） */
const SUPPORTS_IMMERSIVE_MATERIAL: boolean = CURRENT_SDK_VERSION >= 26;

/** 判断是否支持 backgroundBlurStyle（API 10+） */
const SUPPORTS_BACKGROUND_BLUR: boolean = CURRENT_SDK_VERSION >= 10;

/**
 * 是否走系统材质容器路径：仅判断 API 与用户开关，不要求设备实际支持或模块已加载。
 * 这只是布局路径判断；材质实例是否可用应调用 getEnabledSystemMaterial()。
 */
export function shouldUseSystemMaterialPath(immersiveLightEnabled: boolean =
  AppStorage.get<boolean>(KEY_IMMERSIVE_LIGHT_ENABLED) !== false): boolean {
  return SUPPORTS_IMMERSIVE_MATERIAL && immersiveLightEnabled;
}

/** 内容层玻璃化需要材质模块已加载；不要求设备实际支持材质效果。 */
export function shouldUseLoadedMaterialStyle(immersiveLightEnabled: boolean, materialLoaded: boolean): boolean {
  return shouldUseSystemMaterialPath(immersiveLightEnabled) && materialLoaded;
}

/** 预创建的材质实例缓存（surface → Material），动态 import 成功后填充。 */
const materialCache: Record<string, uiMaterial.Material> = {};

/**
 * 异步动态加载 uiMaterial 模块（幂等，可重复调用）。
 * API 26+：加载成功并完成结构校验/实例预创建后写入 AppStorage 加载信号；
 * API 23-：模块不存在，reject 被捕获，静默走 backgroundBlurStyle 降级分支。
 * ⚠️ 全路径防御：结构异常/实例创建失败均不写加载信号，页面继续走 blur 分支，保证不闪退。
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
        materialCache['bar'] = new mod.ImmersiveMaterial({ style: mod.ImmersiveStyle.ULTRA_THIN });
        materialCache['body'] = new mod.ImmersiveMaterial({ style: mod.ImmersiveStyle.ULTRA_THIN });
        materialCache['card'] = new mod.ImmersiveMaterial({ style: mod.ImmersiveStyle.ULTRA_THIN });
        // 浮动操作按钮：官方「纯色 + 质感」组合——
        // materialColor 用不透明控件纯色（color_bg_action，亮浅灰/暗深灰蓝，随主题切换），
        // 提供在卡片上清晰可辨的背板；不透明色会遮住材质滤镜（无模糊透出），
        // 但保留质感部分：交互形变 + 点光源 + 默认阴影。
        // 不要用 backgroundColor 叠色（材质生效时会被还原为透明，且会覆盖光感）。
        const actionLightEffect: uiMaterial.LightEffectOptions = {};
        materialCache['action'] = new mod.ImmersiveMaterial({
          style: mod.ImmersiveStyle.ULTRA_THIN,
          materialColor: $r('app.color.color_bg_action'),
          interactive: true,
          lightEffect: actionLightEffect
        });
        // Sheet 与弹窗背板使用同一级别，兼顾下层透出与正文可读性。
        materialCache['sheet'] = new mod.ImmersiveMaterial({ style: mod.ImmersiveStyle.THICK });
        materialCache['toast'] = new mod.ImmersiveMaterial({ style: mod.ImmersiveStyle.ULTRA_THIN });
        // 弹窗包含 CustomDialog 与系统确认框，和 Sheet 共用材质等级。
        materialCache['dialog'] = new mod.ImmersiveMaterial({ style: mod.ImmersiveStyle.THICK });
        // 菜单（bindMenu/Menu）：挂在 ContextMenuOptions.systemMaterial（MenuOptions 继承），
        // 不是 Menu 组件通用属性。
        materialCache['menu'] = new mod.ImmersiveMaterial({ style: mod.ImmersiveStyle.ULTRA_THIN });
        // 设备能力诊断：部分设备（典型为 SMOOTH 低算力模拟器）isImmersiveMaterialSupported=false，
        // 官方明确此时 systemMaterial「can be set but has no effect」。该结果仅作诊断；
        // 实际渲染统一以 API、用户开关及材质实例是否已创建为准。
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
        // 实例已全部预创建；系统决定实际材质效果，组件只订阅此加载信号。
        AppStorage.setOrCreate(KEY_MATERIAL_LOADED, true);
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

/** 按统一闸门获取指定表面材质；未加载时返回 undefined，由调用方走降级样式。 */
export function getEnabledSystemMaterial(
  surface: 'bar' | 'body' | 'card' | 'action' | 'sheet' | 'toast' | 'dialog' | 'menu',
  immersiveLightEnabled: boolean = AppStorage.get<boolean>(KEY_IMMERSIVE_LIGHT_ENABLED) !== false
): uiMaterial.Material | undefined {
  if (!shouldUseSystemMaterialPath(immersiveLightEnabled) || AppStorage.get<boolean>(KEY_MATERIAL_LOADED) !== true) {
    return undefined;
  }
  return materialCache[surface];
}

/**
 * 弹窗专用：材质实例可用时返回 dialog 材质（挂到 CustomDialogControllerOptions /
 * promptAction.showDialog 等 options 的 systemMaterial 字段），否则返回 undefined
 * （字段缺省即系统纯色弹窗）。可在组件字段初始化期安全调用：未就绪时返回 undefined。
 */
export function getDialogMaterial(immersiveLightEnabled: boolean =
  AppStorage.get<boolean>(KEY_IMMERSIVE_LIGHT_ENABLED) !== false): uiMaterial.Material | undefined {
  return getEnabledSystemMaterial('dialog', immersiveLightEnabled);
}

/**
 * 菜单专用：材质可用时返回 menu 材质，挂到 bindMenu 第二参
 * MenuOptions（继承自 ContextMenuOptions）的 systemMaterial 字段；未加载返回 undefined，
 * 由调用方保留原有的 Menu 降级样式。
 */
function getMenuMaterial(immersiveLightEnabled: boolean =
  AppStorage.get<boolean>(KEY_IMMERSIVE_LIGHT_ENABLED) !== false): uiMaterial.Material | undefined {
  return getEnabledSystemMaterial('menu', immersiveLightEnabled);
}

/** 构造 MenuOptions；API 26 属性赋值留在 util 内，兼顾低版本兼容与编译器检查。 */
export function withImmersiveMenuMaterial(options: MenuOptions): MenuOptions {
  if (deviceInfo.apiAvailable('26.0.0')) {
    const material = getMenuMaterial();
    if (material !== undefined) {
      options.systemMaterial = material;
    }
  }
  return options;
}

/** Select 下拉菜单的 API 26 材质与降级模糊统一在此设置，避免页面直接调用高版本接口。 */
export const IMMERSIVE_SELECT_MENU_MODIFIER: AttributeModifier<SelectAttribute> = {
  applyNormalAttribute(instance: SelectAttribute): void {
    const material = getMenuMaterial();
    if (deviceInfo.apiAvailable('26.0.0')) {
      instance.menuSystemMaterial(material);
    }
    instance.menuBackgroundBlurStyle(material ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THICK);
  }
};

/**
 * 自定义弹窗（@CustomDialog）背板配置：取出返回值的三个字段分别赋给
 * CustomDialogControllerOptions 的同名字段（ArkTS 禁用对象展开，不能 ...spread）。
 *
 * 关键：模糊必须挂在 controller options（系统 dialog 容器，与 bindSheet/promptAction 同渲染路径）
 * 上，低算力设备/模拟器才有真实高斯模糊；挂在 @CustomDialog 内容根节点上无效——
 * dialog 内容子树采样不到下层页面，只会看到 BlurStyle 自带的不透明 tint 白底。
 *
 * - 沉浸材质可用：统一材质背板 + 内容透明
 * - 降级（旧系统/模块未加载/开关关闭）：系统容器 COMPONENT_THICK 模糊 + 80% 弹窗底色保证可读性
 */
export interface DialogBackgroundOptions {
  systemMaterial: uiMaterial.Material | undefined;
  backgroundColor: ResourceColor;
  backgroundBlurStyle: BlurStyle | undefined;
}

export function getDialogBackgroundOptions(): DialogBackgroundOptions {
  const dialogMaterial = getDialogMaterial();
  if (dialogMaterial !== undefined) {
    return {
      systemMaterial: dialogMaterial,
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
