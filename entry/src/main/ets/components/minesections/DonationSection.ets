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
 * 「捐赠」板块：一次性捐赠（消耗型）与持续支持（自动续期订阅）。
 * 是否展示由父组件按 IAP 环境检查结果决定；本组件只负责交互与购买。
 *
 * 自动续期订阅先展示订阅详情面板（金额/周期/《自动续费服务协议》/取消流程），
 * 用户确认后才拉起收银台，满足应用市场对自动续费商品的展示要求。
 */
@Component
export struct DonationSection {
  // 订阅详情面板。
  @State showSubscriptionSheet: boolean = false;
  // 自动续费服务协议面板。
  @State showAgreementSheet: boolean = false;
  // 购买进行中：避免连点重复调用 IAP 触发限流（1001860004）。
  @State purchasing: boolean = false;
  @StorageProp(KEY_IMMERSIVE_LIGHT_ENABLED) immersiveLightEnabled: boolean = true;
  @StorageProp(KEY_MATERIAL_LOADED) immersiveMaterialLoaded: boolean = false;
  // 《自动续费服务协议》正文，购买页可随时查看。
  private readonly agreementText: string = [
    '一、服务说明：本协议适用于「及时通知」应用内提供的「持续支持」自动续期订阅商品。订阅为自愿行为，不订阅不影响应用基础功能的使用。',
    '二、订阅周期与价格：订阅周期为 1 年，价格以应用内订阅页面及华为收银台展示为准。订阅成功后，华为将通过您选择的付款方式扣款。',
    '三、自动续费：订阅到期前 24 小时内，华为将通过您绑定的付款方式自动扣取下一周期费用并延长服务期，具体扣款时间以华为应用内支付系统为准。',
    '四、取消方式：您可随时取消自动续费，路径为「设置 → 华为账号 → 付款与账单 → 订阅 → 及时通知 → 取消订阅」。取消后不再自动续费，已支付的当前周期费用不予退还，权益持续至当前周期结束。',
    '五、价格调整：若订阅价格发生调整，华为将在续费前通过应用内或消息方式告知；您不同意调整价格的，可在续费前取消订阅。',
    '六、退款说明：订阅权益为即时交付的虚拟商品，原则上不支持退款。如因系统异常重复扣款或未获得相应权益，可通过应用内「反馈问题」联系我们，或通过华为应用内支付渠道申请售后。',
    '七、权益范围：「持续支持」属于对作者的自愿捐赠性支持，不承诺提供额外的付费功能或内容，订阅期内也不影响应用已有功能的免费使用。',
    '八、协议变更与联系：本协议内容可能随服务调整而更新，更新后将在应用内公布。如有疑问，可通过应用内「反馈问题」与我们联系。'
  ].join('\n\n');

  build() {
    Column({ space: 12 }) {
      SettingGroupTitle({ title: '捐赠', hint: '不捐赠不影响使用' });

      SettingGroup() {
        // 一次性捐赠：消耗型商品，可重复购买，点击直接拉起收银台。
        SettingCell({
          title: '一次性捐赠', icon: $r('app.media.handshake'),
          clickable: true, onActivate: () => this.doDonate('one_time')
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
          title: '持续支持', icon: $r('app.media.heart_handshake'),
          clickable: true, onActivate: () => this.openSubscriptionSheet()
        }) {
          Row({ space: 4 }) {
            Text('￥6/年')
              .fontSize(14)
              .fontColor($r('app.color.color_text_secondary'));
            SettingArrow();
          }
        }
      }
    }
    .width('100%')
    .bindSheet(this.showSubscriptionSheet, this.subscriptionSheetBuilder(), {
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
        this.showSubscriptionSheet = false;
      }
    });
  }

  // 订阅详情面板：合规展示付费金额、续费周期、自动续费协议与取消流程。
  @Builder
  subscriptionSheetBuilder() {
    Column({ space: 20 }) {
      Column({ space: 6 }) {
        Text('持续支持')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.color_text_primary'))
          .width('100%');
        Text('自愿订阅，不影响应用免费功能使用。')
          .fontSize(13)
          .fontColor($r('app.color.color_text_secondary'))
          .width('100%');
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start);

      Column({ space: 12 }) {
        this.subscriptionInfoRow('服务内容', '支持作者持续维护应用');
        this.subscriptionInfoRow('订阅周期', '1 年，到期前 24 小时自动续费');
        this.subscriptionInfoRow('付款金额', '￥6.00 / 年');
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .backgroundColor($r('app.color.color_bg_surface_glass'))
      .borderRadius(12);

      Column() {
        Row({ space: 4 }) {
          Text('《自动续费服务协议》')
            .fontSize(14)
            .fontColor($r('app.color.color_brand'));
          Blank();
          Image($r('app.media.arrow_right'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.color_text_tertiary'))
            .draggable(false);
        }
        .width('100%')
        .padding({ top: 2, bottom: 14 })
        .onClick(() => {
          this.showAgreementSheet = true;
        });

        Divider()
          .color($r('app.color.color_border_subtle'))
          .strokeWidth(1);

        Column({ space: 8 }) {
          Text('如何取消自动续费')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.color_text_primary'))
            .width('100%');
          Text('设置 → 华为账号 → 付款与账单 → 订阅 → 及时通知 → 取消订阅')
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.color_text_secondary'))
            .width('100%');
          Text('取消后不再自动续费，当前订阅周期内权益仍然有效。')
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
        Button(this.purchasing ? '正在拉起支付…' : '确认订阅 ￥6.00 / 年')
          .width('100%')
          .height(46)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.color_brand'))
          .enabled(!this.purchasing)
          .onClick(() => this.confirmYearly());

        Text('订阅由华为应用内支付提供，可在华为账号中随时管理')
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
  subscriptionInfoRow(label: string, value: string) {
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
        Text('自动续费服务协议')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.color_text_primary'));
        Blank();
        Button('关闭')
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
        Text(this.agreementText)
          .fontSize(13)
          .lineHeight(21)
          .fontColor($r('app.color.color_text_secondary'))
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

  // 打开订阅详情面板；购买进行中不重复打开。
  private openSubscriptionSheet(): void {
    if (this.purchasing) {
      return;
    }
    this.showSubscriptionSheet = true;
  }

  // 用户在订阅详情面板确认后才拉起收银台。
  private async confirmYearly(): Promise<void> {
    this.showSubscriptionSheet = false;
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
      showToast(uiCtx, '上下文获取失败');
      return;
    }
    this.purchasing = true;
    try {
      if (type === 'one_time') {
        await DonationService.purchaseOneTime(ctx);
      } else {
        await DonationService.purchaseYearly(ctx);
      }
      showToast(uiCtx, '感谢你的支持！', 2000);
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, 'DonationSection', '捐赠失败：code=%{public}d msg=%{public}s', be.code, msg);
      // 用户取消不提示错误。
      if (be.code === iap.IAPErrorCode.USER_CANCELED) {
        return;
      } else if (be.code === iap.IAPErrorCode.ACCOUNT_NOT_LOGGED_IN) {
        showToast(uiCtx, '请先登录华为账号');
      } else if (be.code === iap.IAPErrorCode.ACCOUNT_TERRITORY_NOT_SUPPORTED) {
        showToast(uiCtx, '当前地区不支持捐赠');
      } else {
        showToast(uiCtx, '捐赠失败，请稍后重试');
      }
    } finally {
      this.purchasing = false;
    }
  }
}
