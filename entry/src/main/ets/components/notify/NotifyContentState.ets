import { ExternalLinkService, USE_DOCS_URL } from '../../services/ExternalLinkService';
import { AppContextStore } from '../../common/AppContextStore';
import { PreferencesUtil } from '../../utils/PreferencesUtil';
import showToast from '../showToast';

/** 通知列表的引导、加载、错误与空状态视图。 */
@Component
export struct NotifyContentState {
  @Prop mode: string = 'empty';
  @Prop errorMsg: string = '';
  // 同步各空状态实例的确认结果，旧读取不能覆盖同一会话中刚完成的确认。
  @StorageLink(PreferencesUtil.KEY_FIRST_USE_GUIDE_ACKNOWLEDGED) private guideAcknowledged: boolean = false;
  @State private guidePreferenceLoaded: boolean = false;
  @State private openingGuide: boolean = false;
  private guideViewMounted: boolean = false;
  private guideGeneration: number = 0;
  onRetry: () => void = () => {
  };

  aboutToAppear(): void {
    this.guideViewMounted = true;
    this.loadGuideAcknowledgement(++this.guideGeneration);
  }

  aboutToDisappear(): void {
    this.guideViewMounted = false;
    this.guideGeneration++;
  }

  build() {
    if (this.shouldShowFirstUseGuide()) {
      // 较小的可用区域允许整体滚动，保证指南按钮和错误重试都可见。
      Scroll() {
        Column({ space: 24 }) {
          this.firstUseGuide();
          if (this.mode !== 'empty') {
            this.contentStatus();
          }
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .padding({ top: 24, bottom: 24 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      }.width('100%').height('100%').scrollBar(BarState.Off);
    } else {
      Column() {
        this.contentStatus();
      }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center);
    }
  }

  /** 本地加载结束后再显示新手提示，已有通知的用户不因初始化空快照闪现欢迎文案。 */
  private shouldShowFirstUseGuide(): boolean {
    return this.guidePreferenceLoaded && !this.guideAcknowledged && this.mode !== 'loading';
  }

  /** 不写回 false，防止晚到的旧读取撤销其它实例刚完成的确认。 */
  private async loadGuideAcknowledgement(generation: number): Promise<void> {
    const value: string = await PreferencesUtil.getString(null,
      PreferencesUtil.KEY_FIRST_USE_GUIDE_ACKNOWLEDGED, 'false');
    if (!this.guideViewMounted || generation !== this.guideGeneration) {
      return;
    }
    if (value === 'true') {
      AppStorage.setOrCreate(PreferencesUtil.KEY_FIRST_USE_GUIDE_ACKNOWLEDGED, true);
    }
    this.guidePreferenceLoaded = true;
  }

  /** 点击查看即确认引导；写盘失败仍打开指南，保留欢迎提示供下次重试。 */
  private async openUseGuide(): Promise<void> {
    if (!this.guideViewMounted || this.openingGuide) {
      return;
    }
    this.openingGuide = true;
    const generation: number = this.guideGeneration;
    try {
      const saved: boolean = await PreferencesUtil.putString(null,
        PreferencesUtil.KEY_FIRST_USE_GUIDE_ACKNOWLEDGED, 'true');
      // 即使空状态重建，也把这次点击的持久确认结果同步给新实例。
      if (saved) {
        AppStorage.setOrCreate(PreferencesUtil.KEY_FIRST_USE_GUIDE_ACKNOWLEDGED, true);
      }
      if (!this.guideViewMounted || generation !== this.guideGeneration) {
        return;
      }
      if (!saved) {
        showToast(this.getUIContext(), $r('app.string.ntf_save_failed_retry'));
      }
      await ExternalLinkService.openSharePage(this.getUIContext(), USE_DOCS_URL,
        this.localizedGuideTitle());
    } finally {
      if (this.guideViewMounted && generation === this.guideGeneration) {
        this.openingGuide = false;
      }
    }
  }

  /** 欢迎内容只有一个主要动作，不将新手引导绑定在 Token 或网络错误上。 */
  @Builder
  private firstUseGuide() {
    Column({ space: 12 }) {
      Text($r('app.string.ntf_welcome_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.color_text_primary'))
        .textAlign(TextAlign.Center)
        .width('100%');
      Text($r('app.string.ntf_welcome_subtitle'))
        .fontSize(14)
        .lineHeight(22)
        .fontColor($r('app.color.color_text_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%');
      Button($r('app.string.ntf_view_guide'))
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.color_brand'))
        .enabled(!this.openingGuide)
        .margin({ top: 8 })
        .onClick(() => this.openUseGuide());
      // 说明查看后不再提示，并指引用户从服务页再次打开指南。
      Text($r('app.string.ntf_welcome_hint'))
        .fontSize(12)
        .lineHeight(20)
        .fontColor($r('app.color.color_text_hint'))
        .textAlign(TextAlign.Center)
        .width('100%');
    }
    .width('100%').constraintSize({ maxWidth: 320 }).padding({ left: 24, right: 24 })
    .alignItems(HorizontalAlign.Center);
  }

  /** openSharePage 的标题参数仅接受 string，按当前语言同步取回资源文案。 */
  private localizedGuideTitle(): string {
    const context = AppContextStore.getInstance().getContext();
    return context ? context.resourceManager.getStringSync($r('app.string.ntf_guide_title').id) : '';
  }

  /** 欢迎提示下保留实际连接和错误状态，确认后沿用原有空状态展示。 */
  @Builder
  private contentStatus() {
    Column({ space: 12 }) {
      if (this.mode === 'guide') {
        Text($r('app.string.ntf_no_client_token')).fontSize(16).fontColor($r('app.color.color_text_tertiary'));
        Text($r('app.string.ntf_no_client_token_desc')).fontSize(13)
          .fontColor($r('app.color.color_text_hint')).textAlign(TextAlign.Center).width('70%');
      } else if (this.mode === 'loading') {
        LoadingProgress().width(40).height(40).color($r('app.color.color_brand'));
        Text($r('app.string.common_loading')).fontSize(13).fontColor($r('app.color.color_text_hint'));
      } else if (this.mode === 'connecting') {
        // 本地加载已结束，远端同步以独立状态呈现，不再用全屏转圈冒充页面加载。
        Text($r('app.string.ntf_connecting')).fontSize(15).fontColor($r('app.color.color_text_hint'));
        Text($r('app.string.ntf_connecting_desc')).fontSize(13).fontColor($r('app.color.color_text_hint'));
      } else if (this.mode === 'error') {
        Text(this.errorMsg)
          .fontSize(14)
          .fontColor($r('app.color.color_error'))
          .textAlign(TextAlign.Center)
          .width('80%');
        Text($r('app.string.ntf_pull_to_retry')).fontSize(13)
          .fontColor($r('app.color.color_brand')).padding(8).onClick(() => this.onRetry());
      } else {
        Text($r('app.string.ntf_no_notifications')).fontSize(15).fontColor($r('app.color.color_text_hint'));
      }
    }
    .width('100%').alignItems(HorizontalAlign.Center);
  }
}
