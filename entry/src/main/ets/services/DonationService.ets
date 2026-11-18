import { common } from '@kit.AbilityKit';
import { iap } from '@kit.IAPKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DOMAIN } from '../common/Constant';
import { JwsUtil } from '../utils/JwsUtil';

const TAG: string = 'DonationService';

/**
 * 捐赠商品 ID。
 * 需在 AGC「应用内支付服务」中创建对应商品并把此处替换为真实商品 ID。
 * 商品 ID 在 AGC 配置商品时由开发者自定义，全局唯一。
 */
// 一次性捐赠 6 元（消耗型商品，可重复购买）
const PRODUCT_ID_ONE_TIME: string = 'donation_one_time_6';
// 持续捐赠 6 元/年（自动续期订阅商品）
const PRODUCT_ID_YEARLY: string = 'donation_yearly_6';

/** PurchaseData 中可能携带 order 字段的结构（顶层或 data 内）。 */
interface InAppOrder {
  purchaseToken?: string;
  purchaseOrderId?: string;
  purchaseOrderRevocationReasonCode?: number;
}

/** IAP 的 PurchaseData JSON：jwsPurchaseOrder 或 data 两者之一携带订单。 */
interface RawPurchaseData extends InAppOrder {
  jwsPurchaseOrder?: string;
  data?: string;
}

/** 解析出的订单：仅保留确认发货所需字段。 */
interface PurchaseOrder {
  purchaseToken: string;
  purchaseOrderId: string;
  revoked: boolean;
}

/**
 * 捐赠服务：封装华为 IAP Kit 的购买与发货流程。
 * 纯客户端处理：支付完成后解析订单并调用 finishPurchase 确认发货。
 */
export class DonationService {
  /** 检查当前华为账号所在地区是否支持 IAP（目前仅中国大陆）。不支持时隐藏捐赠入口。 */
  static async isEnvironmentSupported(ctx: common.UIAbilityContext): Promise<boolean> {
    try {
      await iap.queryEnvironmentStatus(ctx);
      return true;
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'IAP 环境检查失败：%{public}s', msg);
      return false;
    }
  }

  /** 购买一次性捐赠（消耗型商品）。 */
  static purchaseOneTime(ctx: common.UIAbilityContext): Promise<void> {
    return DonationService.purchase(ctx, PRODUCT_ID_ONE_TIME, iap.ProductType.CONSUMABLE);
  }

  /** 购买持续捐赠（自动续期订阅商品）。 */
  static purchaseYearly(ctx: common.UIAbilityContext): Promise<void> {
    return DonationService.purchase(ctx, PRODUCT_ID_YEARLY, iap.ProductType.AUTORENEWABLE);
  }

  /**
   * 拉起华为收银台并完成购买。
   * createPurchase 失败会抛出 BusinessError 供调用方提示；确认发货失败仅记录日志，
   * 由下次启动的补发货流程重试。
   */
  private static async purchase(
    ctx: common.UIAbilityContext, productId: string, productType: iap.ProductType
  ): Promise<void> {
    const result: iap.CreatePurchaseResult = await iap.createPurchase(ctx, {
      productId: productId,
      productType: productType
    });
    const order: PurchaseOrder | undefined = DonationService.parseOrder(result.purchaseData);
    if (!order) {
      hilog.warn(DOMAIN, TAG, '未能从 purchaseData 解析订单，跳过发货');
      return;
    }
    if (order.revoked) {
      hilog.info(DOMAIN, TAG, '订单已退款，跳过发货');
      return;
    }
    await DonationService.finishPurchase(ctx, productType, order);
  }

  /** 确认发货：通知 IAP 服务器更新发货状态，完成购买流程。 */
  private static async finishPurchase(
    ctx: common.UIAbilityContext, productType: iap.ProductType, order: PurchaseOrder
  ): Promise<void> {
    try {
      await iap.finishPurchase(ctx, {
        productType: productType,
        purchaseToken: order.purchaseToken,
        purchaseOrderId: order.purchaseOrderId
      });
      hilog.info(DOMAIN, TAG, '确认发货成功：%{public}s', order.purchaseOrderId);
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      if (be.code === iap.IAPErrorCode.PURCHASE_FINISHED) {
        hilog.info(DOMAIN, TAG, '订单已确认发货，无需重复：%{public}s', order.purchaseOrderId);
        return;
      }
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '确认发货失败：code=%{public}d msg=%{public}s', be.code, msg);
    }
  }

  /** 启动时补发货：查询已付款但未确认的订单，避免用户已支付却未完成流程。 */
  static async replenishUnfinished(ctx: common.UIAbilityContext): Promise<void> {
    for (const productType of [iap.ProductType.CONSUMABLE, iap.ProductType.AUTORENEWABLE]) {
      try {
        const result: iap.QueryPurchaseResult = await iap.queryPurchases(ctx, {
          productType: productType,
          queryType: iap.PurchaseQueryType.UNFINISHED
        });
        for (const purchaseData of result.purchaseDataList ?? []) {
          const order: PurchaseOrder | undefined = DonationService.parseOrder(purchaseData);
          if (!order || order.revoked) {
            continue;
          }
          await DonationService.finishPurchase(ctx, productType, order);
        }
      } catch (err) {
        const msg: string = err instanceof Error ? err.message : String(err);
        hilog.warn(DOMAIN, TAG, '补发货查询失败：%{public}s', msg);
      }
    }
  }

  /**
   * 从 PurchaseData JSON 解析订单。
   * 兼容两种结构：顶层 jwsPurchaseOrder（JWS 字符串）或 data 字段（InAppPurchaseData JSON）。
   */
  private static parseOrder(purchaseData: string): PurchaseOrder | undefined {
    if (!purchaseData) {
      return undefined;
    }
    let root: RawPurchaseData;
    try {
      root = JSON.parse(purchaseData) as RawPurchaseData;
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '解析 purchaseData 失败：%{public}s', msg);
      return undefined;
    }
    if (root.jwsPurchaseOrder) {
      const payload: string = JwsUtil.decodePayload(root.jwsPurchaseOrder);
      const fromJws: PurchaseOrder | undefined = DonationService.orderFromJson(payload);
      if (fromJws) {
        return fromJws;
      }
    }
    if (root.data) {
      const fromData: PurchaseOrder | undefined = DonationService.orderFromJson(root.data);
      if (fromData) {
        return fromData;
      }
    }
    return DonationService.toOrder(root);
  }

  private static orderFromJson(json: string): PurchaseOrder | undefined {
    if (!json) {
      return undefined;
    }
    try {
      return DonationService.toOrder(JSON.parse(json) as InAppOrder);
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '解析订单 JSON 失败：%{public}s', msg);
      return undefined;
    }
  }

  private static toOrder(o: InAppOrder): PurchaseOrder | undefined {
    if (!o.purchaseToken || !o.purchaseOrderId) {
      return undefined;
    }
    const reason: number = o.purchaseOrderRevocationReasonCode ?? 0;
    return { purchaseToken: o.purchaseToken, purchaseOrderId: o.purchaseOrderId, revoked: reason !== 0 };
  }
}
