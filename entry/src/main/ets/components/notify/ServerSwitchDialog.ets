import { TextModifier } from '@kit.ArkUI';
import { hdsMaterial, HdsListItemCard, HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, SuffixRadio } from '@kit.UIDesignKit';
import { ServerEntry } from '../../model/ServerEntry';
import { ServerManager } from '../../services/ServerManager';
import { extractHost } from '../../utils/ServerUrlUtil';
import { KEY_IMMERSIVE_LIGHT_ENABLED, KEY_MATERIAL_LOADED, shouldUseLoadedMaterialStyle,
  shouldUseSystemMaterialPath } from '../../utils/ImmersiveUtil';

// 空 builder 占位（controller 字段默认值，避免 SDK 注入前的空引用崩溃）
@Builder
function emptySwitchDialogBuilder(): void {
}

// HdsListItemCard 内置左右内缩（卡片相对列表容器的标准外边距），弹窗左右边距直接沿用该值，
// 不再在容器上叠加水平 padding，避免「容器 padding + 卡片内缩」双重缩进
const CARD_SIDE_INSET: number = 20;
// 双行卡片高度（默认自适应约 81vp 偏松，收紧到 68vp）
const CARD_HEIGHT: number = 68;
// 列表最大高度：超出后列表内部上下滚动（与服务器设置弹窗一致，约 4 行）
const LIST_MAX_HEIGHT: number = 280;

/**
 * 「切换通知服务」弹窗（首页标题点击进入）。
 * 仅承载视图范围单选：首项「全部通知」=聚合所有服务器，其后为各服务器（选中=只看该服务器）。
 * 列表行使用 HDS HdsListItemCard：设备沉浸材质生效时保留 HDS 默认卡片表面；
 * 其余情况（旧系统/低算力/开关关）卡片用 color_bg_card_glass（深色为比面板亮一档的抬升色，
 * 避免与弹窗面板同基色 alpha 合成后糊在一起）/选中 color_bg_selected_glass，
 * 未选中行 color_border_default 描边，透出弹窗背板；背板在 API 26+ 且开关开启时
 * 与 Sheet 一样通过统一工具传入 ULTRA_THIN 材质，设备最终效果由系统决定。
 * 卡片降级时面板本身再加 1px color_border_subtle 细描边，深色下勾出面板轮廓。
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
    return 64 + Math.min((this.serverList.length + 1) * (CARD_HEIGHT + 8), LIST_MAX_HEIGHT) + 24;
  }

  // 「全部通知」行：沉浸分支用 HDS 默认卡片表面，降级分支用玻璃色+描边
  @Builder
  allCard(): void {
    if (shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)) {
      HdsListItemCard({
        textItem: {
          primaryText: { text: '全部通知' },
          secondaryText: { text: '聚合展示所有服务器的通知' },
        },
        suffixItem: new SuffixRadio({
          isCheck: this.isAllSelected(),
          selectColor: $r('app.color.color_brand'),
          onClick: (): void => {
            this.selectAll();
          },
        }),
        onClick: (): void => {
          this.selectAll();
        },
        cardHeight: CARD_HEIGHT,
        cardBorderRadius: 10,
      })
        .width('100%');
    } else {
      HdsListItemCard({
        textItem: {
          primaryText: {
            text: '全部通知',
            modifier: this.isAllSelected() ? new TextModifier().fontColor($r('app.color.color_brand')) : undefined,
          },
          secondaryText: { text: '聚合展示所有服务器的通知' },
        },
        suffixItem: new SuffixRadio({
          isCheck: this.isAllSelected(),
          selectColor: $r('app.color.color_brand'),
          onClick: (): void => {
            this.selectAll();
          },
        }),
        onClick: (): void => {
          this.selectAll();
        },
        cardHeight: CARD_HEIGHT,
        // 深色下降级：未选中卡片用抬升玻璃（color_bg_card_glass，比面板亮一档，
        // 不能与面板同基色——同基色仅透明度不同时两层 alpha 合成会收敛成一个色、糊在一起）
        cardBackgroundColor: this.isAllSelected()
          ? $r('app.color.color_bg_selected_glass') : $r('app.color.color_bg_card_glass'),
        cardBorderRadius: 10,
      })
        .width('100%')
        .border({
          width: 1,
          // 深色下 color_border_subtle 与暗面板对比不足，未选中行用 default 勾边
          color: this.isAllSelected() ? $r('app.color.color_brand') : $r('app.color.color_border_default'),
        });
    }
  }

  // 服务器行：主标题为名称（无名时取 host），副标题为 baseURL
  @Builder
  serverCard(s: ServerEntry): void {
    if (shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)) {
      HdsListItemCard({
        textItem: {
          primaryText: { text: s.name && s.name.length > 0 ? s.name : extractHost(s.baseURL) },
          secondaryText: { text: s.baseURL },
        },
        suffixItem: new SuffixRadio({
          isCheck: this.isServerSelected(s.id),
          selectColor: $r('app.color.color_brand'),
          onClick: (): void => {
            this.selectServer(s);
          },
        }),
        onClick: (): void => {
          this.selectServer(s);
        },
        cardHeight: CARD_HEIGHT,
        cardBorderRadius: 10,
      })
        .width('100%');
    } else {
      HdsListItemCard({
        textItem: {
          primaryText: {
            text: s.name && s.name.length > 0 ? s.name : extractHost(s.baseURL),
            modifier: this.isServerSelected(s.id)
              ? new TextModifier().fontColor($r('app.color.color_brand')) : undefined,
          },
          secondaryText: { text: s.baseURL },
        },
        suffixItem: new SuffixRadio({
          isCheck: this.isServerSelected(s.id),
          selectColor: $r('app.color.color_brand'),
          onClick: (): void => {
            this.selectServer(s);
          },
        }),
        onClick: (): void => {
          this.selectServer(s);
        },
        cardHeight: CARD_HEIGHT,
        // 深色下降级：未选中卡片用抬升玻璃（比面板亮一档，避免与面板同基色 alpha 合成后糊色）
        cardBackgroundColor: this.isServerSelected(s.id)
          ? $r('app.color.color_bg_selected_glass') : $r('app.color.color_bg_card_glass'),
        cardBorderRadius: 10,
      })
        .width('100%')
        .border({
          width: 1,
          // 深色下 color_border_subtle 与暗面板对比不足，未选中行用 default 勾边
          color: this.isServerSelected(s.id) ? $r('app.color.color_brand') : $r('app.color.color_border_default'),
        });
    }
  }

  @Builder
  private serverListScroll() {
    Scroll(this.listScroller) {
      Column({ space: 8 }) {
        this.allCard();
        ForEach(this.serverList, (s: ServerEntry) => {
          this.serverCard(s);
        }, (s: ServerEntry) => s.id)
      }
      .width('100%')
      // HdsListItemCard 自带水平内缩，不在容器上叠加左右 padding。
      .padding({ top: 8, bottom: 16 });
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
    .padding({ left: CARD_SIDE_INSET, right: CARD_SIDE_INSET - 4 });
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
