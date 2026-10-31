import { ExternalLinkService, USE_DOCS_URL } from '../../services/ExternalLinkService';
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
        showToast(this.getUIContext(), '保存失败，请重试');
      }
      await ExternalLinkService.openSharePage(this.getUIContext(), USE_DOCS_URL, '使用指南');
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
      Text('欢迎使用及时通知')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.color_text_primary'))
        .textAlign(TextAlign.Center)
        .width('100%');
      Text('查看使用指南了解如何使用此应用')
        .fontSize(14)
        .lineHeight(22)
        .fontColor($r('app.color.color_text_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%');
      Button('查看使用指南')
        .width('100%')
        .height(44)
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.color_brand'))
        .enabled(!this.openingGuide)
        .margin({ top: 8 })
        .onClick(() => this.openUseGuide());
      // 说明查看后不再提示，并指引用户从服务页再次打开指南。
      Text('点击上方按钮后将不再显示此提示\n后续可点击下方「服务」在文档中查看使用指南')
        .fontSize(12)
        .lineHeight(20)
        .fontColor($r('app.color.color_text_hint'))
        .textAlign(TextAlign.Center)
        .width('100%');
    }
    .width('100%').constraintSize({ maxWidth: 320 }).padding({ left: 24, right: 24 })
    .alignItems(HorizontalAlign.Center);
  }

  /** 欢迎提示下保留实际连接和错误状态，确认后沿用原有空状态展示。 */
  @Builder
  private contentStatus() {
    Column({ space: 12 }) {
      if (this.mode === 'guide') {
        Text('未配置客户端 Token').fontSize(16).fontColor($r('app.color.color_text_tertiary'));
        Text('同步历史通知需要客户端 Token 认证，请检查当前服务的配置').fontSize(13)
          .fontColor($r('app.color.color_text_hint')).textAlign(TextAlign.Center).width('70%');
      } else if (this.mode === 'loading') {
        LoadingProgress().width(40).height(40).color($r('app.color.color_brand'));
        Text('加载中…').fontSize(13).fontColor($r('app.color.color_text_hint'));
      } else if (this.mode === 'connecting') {
        // 本地加载已结束，远端同步以独立状态呈现，不再用全屏转圈冒充页面加载。
        Text('正在连接服务器…').fontSize(15).fontColor($r('app.color.color_text_hint'));
        Text('连接完成后自动显示通知').fontSize(13).fontColor($r('app.color.color_text_hint'));
      } else if (this.mode === 'error') {
        Text(this.errorMsg)
          .fontSize(14)
          .fontColor($r('app.color.color_error'))
          .textAlign(TextAlign.Center)
          .width('80%');
        Text('下拉重试').fontSize(13).fontColor($r('app.color.color_brand')).padding(8).onClick(() => this.onRetry());
      } else {
        Text('暂无通知').fontSize(15).fontColor($r('app.color.color_text_hint'));
      }
    }
    .width('100%').alignItems(HorizontalAlign.Center);
  }
}
