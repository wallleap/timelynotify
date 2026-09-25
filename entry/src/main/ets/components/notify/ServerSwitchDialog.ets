import { TextModifier } from '@kit.ArkUI';
import { HdsListItemCard, SuffixRadio } from '@kit.UIDesignKit';
import { ServerEntry } from '../../model/ServerEntry';
import { ServerManager } from '../../services/ServerManager';
import { extractHost } from '../ServerSettingsContent';
import { isImmersiveMaterialActive } from '../../utils/ImmersiveUtil';

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
 * 列表行使用 HDS HdsListItemCard：沉浸材质生效时保留 HDS 默认卡片表面；
 * 降级（旧系统/低算力/开关关）卡片用 color_bg_card_glass（深色为比面板亮一档的抬升色，
 * 避免与弹窗面板同基色 alpha 合成后糊在一起）/选中 color_bg_selected_glass，
 * 未选中行 color_border_default 描边，透出系统容器层的 COMPONENT_THICK 模糊（透明模糊背景）；
 * 降级时面板本身再加 1px color_border_subtle 细描边，深色下勾出面板轮廓。
 * 结构对齐其它弹窗：Scroll 根（整体超高兜底滚动）+ 居中标题与右上角关闭图标 +
 * 定高 List（服务器多时内部滚动）。服务器的增删/Token/加密等管理仍在「我的 → 服务器设置」页。
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
  // 弹窗在点击标题时才构造：此时材质要么已 READY，要么本会话确认走降级，构造期判定一次即可
  private immersive: boolean = isImmersiveMaterialActive();
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

  // 「全部通知」行：沉浸分支用 HDS 默认卡片表面，降级分支用玻璃色+描边
  @Builder
  allCard(): void {
    if (this.immersive) {
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
    if (this.immersive) {
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

  build() {
    Scroll() {
      Column({ space: 14 }) {
        // 顶部：居中标题 + 右上角关闭图标（与其它弹窗一致）
        Stack({ alignContent: Alignment.TopEnd }) {
          Text('切换通知服务')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_text_primary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 6, bottom: 6 });

          Image($r('app.media.close'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.color_text_hint'))
            .padding(4)
            .draggable(false)
            .onClick(() => {
              this.close();
            });
        }
        .width('100%')
        // 关闭图标与卡片外缘对齐（HDS 卡片内置 16~20vp 内缩，取 20vp）
        .padding({ left: CARD_SIDE_INSET, right: CARD_SIDE_INSET - 4 });

        // 列表：服务器数量多时在定高区域内上下滚动
        List({ space: 8 }) {
          ListItem() {
            this.allCard();
          }
          ForEach(this.serverList, (s: ServerEntry) => {
            ListItem() {
              this.serverCard(s);
            }
          }, (s: ServerEntry) => s.id)
        }
          .width('100%')
          .constraintSize({ maxHeight: LIST_MAX_HEIGHT })
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring);
      }
      .width('100%');
    }
    .constraintSize({ maxHeight: '80%' })
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    // 水平方向不再加 padding：HdsListItemCard 自带 16/20vp（随系统版本）卡片内缩
    .padding({ top: 16, bottom: 16, left: 0, right: 0 })
    .backgroundColor(Color.Transparent)
    .borderRadius(14)
    // 仅降级分支：内容根填充仍恒透明（背板模糊只能挂 controller 容器），
    // 深色下降级面板色与页面同为深炭、仅靠模糊边界难分辨，用 1px 细描边勾出圆角面板轮廓；
    // 沉浸材质分支材质自带边缘，不画
    .borderWidth(this.immersive ? 0 : 1)
    .borderColor($r('app.color.color_border_subtle'));
  }
}
