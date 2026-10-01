import { hdsMaterial, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { ServerEntry } from '../../model/ServerEntry';
import { ServerManager } from '../../services/ServerManager';
import { extractHost } from '../../utils/ServerUrlUtil';
import { KEY_IMMERSIVE_LIGHT_ENABLED, KEY_MATERIAL_LOADED, shouldUseLoadedMaterialStyle,
  shouldUseSystemMaterialPath } from '../../utils/ImmersiveUtil';

// 空 builder 占位（controller 字段默认值，避免 SDK 注入前的空引用崩溃）
@Builder
function emptySwitchDialogBuilder(): void {
}

// 弹窗内容左右内边距：普通列表行不再自带内缩，由滚动容器统一叠加，标题左右边缘与列表行对齐
const CONTENT_SIDE_INSET: number = 20;
// 列表行内容左右内边距（文字与单选指示器到行边缘的距离）
const ROW_CONTENT_PADDING: number = 16;
// 双行行高（收紧到 68vp）
const ROW_HEIGHT: number = 68;
// 列表最大高度：超出后列表内部上下滚动（与服务器设置弹窗一致，约 4 行）
const LIST_MAX_HEIGHT: number = 280;

/**
 * 「切换通知服务」弹窗（首页标题点击进入）。
 * 仅承载视图范围单选：首项「全部通知」=聚合所有服务器，其后为各服务器（选中=只看该服务器）。
 * 列表行为普通 Row，不使用 HDS 卡片，所有分支统一降级样式：
 * 未选中 color_bg_card_glass（深色为比面板亮一档的抬升色，避免与弹窗面板同基色 alpha 合成后
 * 糊在一起）+ color_border_default 描边，选中 color_bg_selected_glass + 品牌色描边与主标题，
 * 透出弹窗背板；单选指示为自绘圆环（选中=品牌色圆环+实心内点，未选中=描边圆环）。
 * 背板在 API 26+ 且开关开启时与 Sheet 一样通过统一工具传入 THICK 材质，设备最终效果由系统决定。
 * 降级时面板本身再加 1px color_border_subtle 细描边，深色下勾出面板轮廓。
 * API 26+ 沉浸分支使用 HDS 固定标题栏、叠放的描边透明关闭按钮和绑定的滚动区；
 * 降级分支保留普通固定标题与关闭图标。服务器的增删/Token/加密等管理在「服务」页。
 */
@CustomDialog
export struct ServerSwitchDialog {
  // controller 由 SDK 自动注入；占位实例作默认值，避免未初始化 NPE
  controller: CustomDialogController = new CustomDialogController({
    builder: emptySwitchDialogBuilder(),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    offset: { dx: 0, dy: 0 },
  });
  @State serverList: ServerEntry[] = [];
  @State currentId: string = '';
  @State viewAll: boolean = true;
  @StorageProp(KEY_IMMERSIVE_LIGHT_ENABLED) private immersiveLightEnabled: boolean = true;
  @StorageProp(KEY_MATERIAL_LOADED) private immersiveMaterialLoaded: boolean = false;
  private listScroller: Scroller = new Scroller();
  private onChange: ((list: ServerEntry[], curId: string) => void) | null = null;

  aboutToAppear(): void {
    this.refresh();
    const mgr: ServerManager = ServerManager.getInstance();
    // 服务器列表/当前选中在弹窗开启期间被其它链路变更时保持回显一致
    this.onChange = (_list: ServerEntry[], _curId: string): void => {
      this.refresh();
    };
    mgr.addChangeListener(this.onChange);
  }

  aboutToDisappear(): void {
    if (this.onChange) {
      ServerManager.getInstance().removeChangeListener(this.onChange);
    }
  }

  private refresh(): void {
    const mgr: ServerManager = ServerManager.getInstance();
    this.serverList = mgr.getList();
    const cur: ServerEntry | null = mgr.getCurrentServer();
    this.currentId = cur ? cur.id : '';
    this.viewAll = mgr.getViewAllMode();
  }

  private isAllSelected(): boolean {
    return this.viewAll;
  }

  private isServerSelected(id: string): boolean {
    return !this.viewAll && id === this.currentId;
  }

  /** 选择「全部通知」：进入聚合视图并关闭弹窗 */
  private selectAll(): void {
    if (!this.viewAll) {
      ServerManager.getInstance().setViewAllMode(true);
    }
    this.close();
  }

  /** 选择某服务器：切到单服务器视图（关闭聚合）并切换当前服务器，然后关闭弹窗 */
  private selectServer(server: ServerEntry): void {
    const mgr: ServerManager = ServerManager.getInstance();
    if (mgr.getViewAllMode()) {
      mgr.setViewAllMode(false);
    }
    if (server.id !== this.currentId) {
      // fire-and-forget：切换结果经 ServerManager listener 通知 NotifyView 刷新
      mgr.switchTo(null, server.id);
    }
    this.close();
  }

  private close(): void {
    try {
      this.controller.close();
    } catch (_err) {
      // 关闭竞态时忽略
    }
  }

  private dialogHeight(): number {
    return 64 + Math.min((this.serverList.length + 1) * (ROW_HEIGHT + 8), LIST_MAX_HEIGHT) + 24;
  }

  // 单选指示器：选中=品牌色圆环+实心内点，未选中=描边圆环（仅展示，点击由整行 onClick 承接）
  @Builder
  private radioIndicator(selected: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      Row()
        .width(20)
        .height(20)
        .borderRadius(10)
        .border({
          width: 2,
          color: selected ? $r('app.color.color_brand') : $r('app.color.color_border_default')
        });
      if (selected) {
        Row()
          .width(10)
          .height(10)
          .borderRadius(5)
          .backgroundColor($r('app.color.color_brand'));
      }
    }
    .width(20)
    .height(20);
  }

  // 通用选项行：所有分支统一降级玻璃样式（选中=选中玻璃+品牌描边/主标题，未选中=抬升玻璃+默认描边）
  @Builder
  private optionRow(primary: string, secondary: string, selected: boolean, onTap: () => void) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(primary)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(selected ? $r('app.color.color_brand') : $r('app.color.color_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(secondary)
          .fontSize(13)
          .fontColor($r('app.color.color_text_hint'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);

      this.radioIndicator(selected);
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: ROW_CONTENT_PADDING, right: ROW_CONTENT_PADDING })
    .backgroundColor(selected ? $r('app.color.color_bg_selected_glass') : $r('app.color.color_bg_card_glass'))
    .borderRadius(10)
    .border({
      width: 1,
      // 深色下 color_border_subtle 与暗面板对比不足，未选中行用 default 勾边
      color: selected ? $r('app.color.color_brand') : $r('app.color.color_border_default')
    })
    .onClick(() => {
      onTap();
    });
  }

  // 「全部通知」行
  @Builder
  private allRow(): void {
    this.optionRow('全部通知', '聚合展示所有服务器的通知', this.isAllSelected(), (): void => {
      this.selectAll();
    });
  }

  // 服务器行：主标题为名称（无名时取 host），副标题为 baseURL
  @Builder
  private serverRow(s: ServerEntry): void {
    this.optionRow(s.name && s.name.length > 0 ? s.name : extractHost(s.baseURL), s.baseURL,
      this.isServerSelected(s.id), (): void => {
        this.selectServer(s);
      });
  }

  @Builder
  private serverListScroll() {
    Scroll(this.listScroller) {
      Column({ space: 8 }) {
        this.allRow();
        ForEach(this.serverList, (s: ServerEntry) => {
          this.serverRow(s);
        }, (s: ServerEntry) => s.id)
      }
      .width('100%')
      // 普通行不再自带水平内缩，容器统一叠加左右内边距，与标题左右边缘对齐
      .padding({ left: CONTENT_SIDE_INSET, right: CONTENT_SIDE_INSET, top: 8, bottom: 16 });
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .clip(!shouldUseSystemMaterialPath(this.immersiveLightEnabled));
  }

  @Builder
  private fallbackTitle() {
    Row() {
      Text('切换通知服务')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.color_text_primary'))
        .layoutWeight(1);
      Image($r('app.media.close'))
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.color_text_hint'))
        .padding(4)
        .draggable(false)
        .onClick(() => this.close());
    }
    .width('100%')
    .height(64)
    .padding({ left: CONTENT_SIDE_INSET, right: CONTENT_SIDE_INSET - 4 });
  }

  @Builder
  private glassCloseButton() {
    Row() {
      Image($r('app.media.close'))
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.color_text_primary'))
        .draggable(false);
    }
    .width(38)
    .height(38)
    .borderRadius(38)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .border({ width: 1, color: $r('app.color.color_border_glass') })
    // 弹窗背板已做模糊；按钮再叠白色模糊会在亮色下变成实心白圆。
    .backgroundColor(Color.Transparent)
    .margin({ top: 12, right: 14 })
    .onClick(() => this.close());
  }

  build() {
    if (shouldUseSystemMaterialPath(this.immersiveLightEnabled)) {
      Stack({ alignContent: Alignment.TopEnd }) {
        HdsNavigation() {
          this.serverListScroll();
        }
        .titleBar({
          enableComponentSafeArea: true,
          content: { title: { mainTitle: '切换通知服务' } },
          style: {
            scrollEffectOpts: {
              enableScrollEffect: true,
              scrollEffectType: ScrollEffectType.GRADIENT_BLUR
            },
            systemMaterialEffect: {
              materialType: hdsMaterial.MaterialType.ADAPTIVE,
              materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
            }
          }
        })
        .hideBackButton(true)
        .titleMode(HdsNavigationTitleMode.MODAL)
        .bindToScrollable([this.listScroller])
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent);

        this.glassCloseButton();
      }
      .width('100%')
      .height(this.dialogHeight())
      .backgroundColor(Color.Transparent)
      .borderRadius(14)
      .clip(true);
    } else {
      Column() {
        this.fallbackTitle();
        this.serverListScroll();
      }
      .width('100%')
      .height(this.dialogHeight())
      .backgroundColor(Color.Transparent)
      .borderRadius(14)
      .clip(true)
      .borderWidth(shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded) ? 0 : 1)
      .borderColor($r('app.color.color_border_subtle'));
    }
  }
}
