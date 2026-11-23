import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { iap } from '@kit.IAPKit';
import { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DOMAIN } from '../../common/Constant';
import { ThemeService } from '../../services/ThemeService';
import { DonationService } from '../../services/DonationService';
import {
  getEnabledSystemMaterial,
  KEY_IMMERSIVE_LIGHT_ENABLED,
  KEY_MATERIAL_LOADED,
  shouldUseLoadedMaterialStyle
} from '../../utils/ImmersiveUtil';
import showToast from '../showToast';
import { SettingGroup } from '../settings/SettingGroup';
import { SettingGroupTitle } from '../settings/SettingGroupTitle';
import { SettingCell } from '../settings/SettingCell';
import { SettingArrow } from '../settings/SettingArrow';
import { SettingDivider } from '../settings/SettingDivider';

/**
 * 捐赠板块的底部面板模式。
 */
enum DonationSheetMode {
  NONE = 0,
  ONE_TIME = 1,
  SUBSCRIPTION = 2
}

/**
 * 「捐赠」板块：一次性捐赠（消耗型）与持续支持（自动续期订阅）。
 * 是否展示由父组件按 IAP 环境检查结果决定；本组件只负责交互与购买。
 *
 * 自动续期订阅先展示订阅详情面板（金额/周期/《自动续费服务协议》/取消流程），
 * 用户勾选同意协议并确认后才拉起收银台，满足应用市场对自动续费商品的展示要求。
 */
@Component
export struct DonationSection {
  // 面板模式：根节点只能挂一个 bindSheet，多个面板共用一个并按模式切换内容。
  @State sheetMode: DonationSheetMode = DonationSheetMode.NONE;
  // 自动续费服务协议面板。
  @State showAgreementSheet: boolean = false;
  // 购买进行中：避免连点重复调用 IAP 触发限流（1001860004）。
  @State purchasing: boolean = false;
  // 用户是否主动勾选同意《自动续费服务协议》，默认不勾选（不得默认同意）。
  @State agreedToAgreement: boolean = false;
  // 用户是否主动勾选确认一次性捐赠须知，默认不勾选（不得默认同意）。
  @State agreedToOneTime: boolean = false;
  @StorageProp(KEY_IMMERSIVE_LIGHT_ENABLED) immersiveLightEnabled: boolean = true;
  @StorageProp(KEY_MATERIAL_LOADED) immersiveMaterialLoaded: boolean = false;
  // 《自动续费服务协议》正文（按段落拆分为资源引用），购买页可随时查看。
  private readonly agreementParagraphs: ResourceStr[] = [
    $r('app.string.mine_donate_agreement_1'),
    $r('app.string.mine_donate_agreement_2'),
    $r('app.string.mine_donate_agreement_3'),
    $r('app.string.mine_donate_agreement_4'),
    $r('app.string.mine_donate_agreement_5'),
    $r('app.string.mine_donate_agreement_6'),
    $r('app.string.mine_donate_agreement_7'),
    $r('app.string.mine_donate_agreement_8')
  ];

  build() {
    Column({ space: 12 }) {
      SettingGroupTitle({
        title: $r('app.string.mine_donate_title'),
        hint: $r('app.string.mine_donate_hint')
      });

      SettingGroup() {
        // 一次性捐赠：消耗型商品，可重复购买；先展示确认面板再拉起收银台。
        SettingCell({
          title: $r('app.string.mine_donate_one_time'), icon: $r('app.media.handshake'),
          clickable: true, onActivate: () => this.openOneTimeSheet()
        }) {
          Row({ space: 4 }) {
            Text('￥6')
              .fontSize(14)
              .fontColor($r('app.color.color_text_secondary'));
            SettingArrow();
          }
        }

        SettingDivider();

        // 持续支持：自动续期订阅商品；先展示订阅详情再拉起收银台。
        SettingCell({
          title: $r('app.string.mine_donate_subscription_title'), icon: $r('app.media.heart_handshake'),
          clickable: true, onActivate: () => this.openSubscriptionSheet()
        }) {
          Row({ space: 4 }) {
            Text($r('app.string.mine_donate_price_year'))
              .fontSize(14)
              .fontColor($r('app.color.color_text_secondary'));
            SettingArrow();
          }
        }
      }
    }
    .width('100%')
    // 根节点只能挂一个 bindSheet，一次性捐赠与订阅面板共用，按 sheetMode 切换内容。
    .bindSheet(this.sheetMode !== DonationSheetMode.NONE, this.donationSheetBuilder(), {
      detents: [SheetSize.FIT_CONTENT, SheetSize.LARGE],
      preferType: SheetType.BOTTOM,
      showClose: false,
      enableFloatingDragBar: true,
      maskColor: shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)
        ? undefined : '#33000000',
      backgroundColor: shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)
        ? Color.Transparent : $r('app.color.color_bg_sheet_blur'),
      blurStyle: shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)
        ? undefined : BlurStyle.COMPONENT_ULTRA_THIN,
      systemMaterial: getEnabledSystemMaterial('sheet', this.immersiveLightEnabled),
      onDisappear: () => {
        this.sheetMode = DonationSheetMode.NONE;
        // 每次关闭后复位，避免下次进入时沿用上一次的同意状态。
        this.agreedToAgreement = false;
        this.agreedToOneTime = false;
      }
    });
  }

  // 按当前模式渲染面板内容。
  @Builder
  donationSheetBuilder() {
    if (this.sheetMode === DonationSheetMode.ONE_TIME) {
      this.oneTimeSheetBuilder();
    } else {
      this.subscriptionSheetBuilder();
    }
  }

  // 订阅详情面板：合规展示付费金额、续费周期、自动续费协议与取消流程。
  @Builder
  subscriptionSheetBuilder() {
    Column({ space: 20 }) {
      Column({ space: 6 }) {
        Text($r('app.string.mine_donate_subscription_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.color_text_primary'))
          .width('100%');
        Text($r('app.string.mine_donate_subscription_desc'))
          .fontSize(13)
          .fontColor($r('app.color.color_text_secondary'))
          .width('100%');
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start);

      Column({ space: 12 }) {
        this.subscriptionInfoRow($r('app.string.mine_donate_service_content'),
          $r('app.string.mine_donate_service_content_value'));
        this.subscriptionInfoRow($r('app.string.mine_donate_cycle'),
          $r('app.string.mine_donate_cycle_value'));
        this.subscriptionInfoRow($r('app.string.mine_donate_payment_amount'),
          $r('app.string.mine_donate_payment_amount_value'));
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .backgroundColor($r('app.color.color_bg_surface_glass'))
      .borderRadius(12);

      Column() {
        Divider()
          .color($r('app.color.color_border_subtle'))
          .strokeWidth(1);

        Column({ space: 8 }) {
          Text($r('app.string.mine_donate_cancel_title'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.color_text_primary'))
            .width('100%');
          Text($r('app.string.mine_donate_cancel_path'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.color_text_secondary'))
            .width('100%');
          Text($r('app.string.mine_donate_cancel_note'))
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.color_text_tertiary'))
            .width('100%');
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 14 });
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start);

      Column({ space: 12 }) {
        // 主动勾选同意，默认不勾选；未勾选时不允许提交订阅。
        Row({ space: 8 }) {
          Checkbox({ name: 'donationAgreement', group: 'donation' })
            .select(this.agreedToAgreement)
            .selectedColor($r('app.color.color_brand'))
            .width(18)
            .height(18)
            .onChange((checked: boolean) => {
              this.agreedToAgreement = checked;
            });

          Text() {
            Span($r('app.string.mine_donate_agree_prefix'));
            Span($r('app.string.mine_donate_agreement_link'))
              .fontColor($r('app.color.color_brand'))
              .onClick(() => {
                this.showAgreementSheet = true;
              });
          }
          .fontSize(12)
          .lineHeight(18)
          .fontColor($r('app.color.color_text_secondary'))
          .layoutWeight(1);
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);

        Button(this.purchasing ? $r('app.string.mine_donate_paying')
          : $r('app.string.mine_donate_confirm_subscription'))
          .width('100%')
          .height(46)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.color_brand'))
          .opacity(this.agreedToAgreement ? 1 : 0.4)
          .enabled(this.agreedToAgreement && !this.purchasing)
          .onClick(() => this.confirmYearly());

        Text($r('app.string.mine_donate_subscription_footnote'))
          .fontSize(11)
          .fontColor($r('app.color.color_text_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center);
      }
      .width('100%');
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 20, right: 20, top: 16, bottom: 20 })
    .backgroundColor(Color.Transparent)
    // 同一节点只能挂一个 bindSheet，协议面板挂到订阅面板的内容节点上。
    .bindSheet(this.showAgreementSheet, this.agreementSheetBuilder(), {
      detents: [SheetSize.LARGE],
      preferType: SheetType.BOTTOM,
      showClose: false,
      enableFloatingDragBar: true,
      maskColor: shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)
        ? undefined : '#33000000',
      backgroundColor: shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)
        ? Color.Transparent : $r('app.color.color_bg_sheet_blur'),
      blurStyle: shouldUseLoadedMaterialStyle(this.immersiveLightEnabled, this.immersiveMaterialLoaded)
        ? undefined : BlurStyle.COMPONENT_ULTRA_THIN,
      systemMaterial: getEnabledSystemMaterial('sheet', this.immersiveLightEnabled),
      onDisappear: () => {
        this.showAgreementSheet = false;
      }
    });
  }

  @Builder
  subscriptionInfoRow(label: ResourceStr, value: ResourceStr) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.color_text_secondary'));
      Blank();
      Text(value)
        .fontSize(13)
        .fontColor($r('app.color.color_text_primary'));
    }
    .width('100%');
  }

  // 自动续费服务协议全文面板。
  @Builder
  agreementSheetBuilder() {
    Column() {
      Row() {
        Text($r('app.string.mine_donate_agreement_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.color_text_primary'));
        Blank();
        Button($r('app.string.common_close'))
          .fontSize(14)
          .fontColor($r('app.color.color_brand'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showAgreementSheet = false;
          });
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Scroll() {
        // 协议正文按段落渲染，段间距以 space 近似原来的空行分隔。
        Column({ space: 12 }) {
          ForEach(this.agreementParagraphs, (paragraph: ResourceStr) => {
            Text(paragraph)
              .fontSize(13)
              .lineHeight(21)
              .fontColor($r('app.color.color_text_secondary'))
              .width('100%');
          })
        }
        .width('100%')
        .margin({ top: 12, bottom: 24 });
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off);
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .backgroundColor(Color.Transparent);
  }

  // 打开一次性捐赠确认面板；购买进行中不重复打开。
  private openOneTimeSheet(): void {
    if (this.purchasing) {
      return;
    }
    this.sheetMode = DonationSheetMode.ONE_TIME;
  }

  // 用户在一次性捐赠确认面板勾选并确认后才拉起收银台。
  private async confirmOneTime(): Promise<void> {
    if (!this.agreedToOneTime) {
      return;
    }
    this.sheetMode = DonationSheetMode.NONE;
    await this.doDonate('one_time');
  }

  // 一次性捐赠确认面板：告知金额、说明是消耗型虚拟商品、不可退款，勾选确认后拉起收银台。
  @Builder
  oneTimeSheetBuilder() {
    Column({ space: 20 }) {
      Column({ space: 6 }) {
        Text($r('app.string.mine_donate_one_time'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.color_text_primary'))
          .width('100%');
        Text($r('app.string.mine_donate_one_time_desc'))
          .fontSize(13)
          .fontColor($r('app.color.color_text_secondary'))
          .width('100%');
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start);

      // 信息卡
      Column({ space: 0 }) {
        Row() {
          Text($r('app.string.mine_donate_payment_amount'))
            .fontSize(13)
            .fontColor($r('app.color.color_text_secondary'));
          Blank();
          Text('￥6.00')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.color_text_primary'));
        }
        .width('100%');
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .backgroundColor($r('app.color.color_bg_card_glass'))
      .borderRadius(12);

      // 主动勾选确认，默认不勾选
      Row({ space: 8 }) {
        Checkbox({ name: 'oneTimeConfirm', group: 'oneTime' })
          .select(this.agreedToOneTime)
          .selectedColor($r('app.color.color_brand'))
          .width(18)
          .height(18)
          .onChange((checked: boolean) => {
            this.agreedToOneTime = checked;
          });

        Text($r('app.string.mine_donate_one_time_confirm_note'))
          .fontSize(12)
          .lineHeight(18)
          .fontColor($r('app.color.color_text_secondary'))
          .layoutWeight(1);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      Button(this.purchasing ? $r('app.string.mine_donate_paying')
        : $r('app.string.mine_donate_confirm_one_time'))
        .width('100%')
        .height(46)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.color_brand'))
        .opacity(this.agreedToOneTime ? 1 : 0.4)
        .enabled(this.agreedToOneTime && !this.purchasing)
        .onClick(() => this.confirmOneTime());

      Text($r('app.string.mine_donate_one_time_footnote'))
        .fontSize(11)
        .fontColor($r('app.color.color_text_tertiary'))
        .width('100%')
        .textAlign(TextAlign.Center);
    }
    .width('100%')
    .padding(20);
  }

  // 打开订阅详情面板；购买进行中不重复打开。
  private openSubscriptionSheet(): void {
    if (this.purchasing) {
      return;
    }
    this.sheetMode = DonationSheetMode.SUBSCRIPTION;
  }

  // 用户在订阅详情面板确认后才拉起收银台。
  private async confirmYearly(): Promise<void> {
    // 未勾选同意《自动续费服务协议》不允许订阅。
    if (!this.agreedToAgreement) {
      return;
    }
    this.sheetMode = DonationSheetMode.NONE;
    await this.doDonate('yearly');
  }

  // 执行捐赠购买；成功后提示感谢，失败按错误码友好提示。
  private async doDonate(type: 'one_time' | 'yearly'): Promise<void> {
    if (this.purchasing) {
      return;
    }
    const uiCtx: UIContext = this.getUIContext();
    const ctx: common.UIAbilityContext | null = ThemeService.getAbilityContext(uiCtx);
    if (!ctx) {
      showToast(uiCtx, $r('app.string.mine_donate_ctx_failed'));
      return;
    }
    this.purchasing = true;
    try {
      if (type === 'one_time') {
        await DonationService.purchaseOneTime(ctx);
      } else {
        await DonationService.purchaseYearly(ctx);
      }
      showToast(uiCtx, $r('app.string.mine_donate_thanks'), 2000);
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, 'DonationSection', '捐赠失败：code=%{public}d msg=%{public}s', be.code, msg);
      // 用户取消不提示错误。
      if (be.code === iap.IAPErrorCode.USER_CANCELED) {
        return;
      } else if (be.code === iap.IAPErrorCode.ACCOUNT_NOT_LOGGED_IN) {
        showToast(uiCtx, $r('app.string.mine_donate_login_required'));
      } else if (be.code === iap.IAPErrorCode.ACCOUNT_TERRITORY_NOT_SUPPORTED) {
        showToast(uiCtx, $r('app.string.mine_donate_region_unsupported'));
      } else {
        showToast(uiCtx, $r('app.string.mine_donate_failed'));
      }
    } finally {
      this.purchasing = false;
    }
  }
}
