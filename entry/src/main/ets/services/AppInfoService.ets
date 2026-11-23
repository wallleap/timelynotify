import { bundleManager, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BuildInfo } from '../generated/BuildInfo';
import { AppContextStore } from '../common/AppContextStore';
import { DOMAIN } from '../common/Constant';

const TAG: string = 'AppInfoSvc';

/** 读取当前语言的字符串资源（构建信息文案）；Context 未就绪时回退空串 */
function tr(res: Resource, arg1?: string | number, arg2?: string | number): string {
  const ctx: common.Context | null = AppContextStore.getInstance().getContext();
  if (ctx === null) {
    return '';
  }
  if (arg1 === undefined) {
    return ctx.resourceManager.getStringSync(res.id);
  }
  if (arg2 === undefined) {
    return ctx.resourceManager.getStringSync(res.id, arg1);
  }
  return ctx.resourceManager.getStringSync(res.id, arg1, arg2);
}

/** 版本信息兜底常量，与 AppScope/app.json5 保持一致，防止 bundleManager 返回空时显示异常 */
const FALLBACK_VERSION_NAME: string = '1.0.0';
const FALLBACK_VERSION_CODE: number = 1000000;

/** 仓库开源地址（MineView 顶部常量搬入服务层，供构建信息页等场景复用） */
export const SOURCE_CODE_URL: string = 'https://github.com/wallleap/timelynotify';

/** 应用版本信息显式类型，满足 ArkTS 对对象字面量的约束 */
export class VersionInfo {
  name: string = FALLBACK_VERSION_NAME;
  code: number = FALLBACK_VERSION_CODE;
}

/**
 * 应用信息 + 构建溯源服务：
 *  - 读取自身版本号（versionName/versionCode）
 *  - 读取签名证书指纹尾 8 位（用于防伪校验）
 *  - 组装构建信息副标题文案
 *  - 组装「点击复制版本信息」完整文本
 *  - 构建云端构建记录页 URL
 *
 * 注意：纯静态方法，无副作用；UI 层负责展示与 Toast 提示。
 */
export class AppInfoService {
  /** 读取自身应用版本号；读取失败或为空时返回兜底常量 */
  static async fetchVersionInfo(): Promise<VersionInfo> {
    try {
      const flags: number = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION;
      const info: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(flags);
      // versionName 可能因 module.json5 未声明 version.name 而空串，非空才覆盖兜底
      const result: VersionInfo = new VersionInfo();
      result.name = (info.versionName && info.versionName.length > 0)
        ? info.versionName : FALLBACK_VERSION_NAME;
      result.code = info.versionCode > 0 ? info.versionCode : FALLBACK_VERSION_CODE;
      hilog.info(DOMAIN, TAG, '版本号读取：name=%{public}s code=%{public}d', result.name, result.code);
      return result;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, 'getBundleInfoForSelf 失败：%{public}s，使用兜底版本', msg);
      // 失败时返回兜底常量，不做 UI 提示
      return new VersionInfo();
    }
  }

  /**
   * 读取签名证书指纹尾 8 位（SHA-256）。
   * 伪造包必然更换签名证书 → 指纹必变；与 README/Release 公布的指纹比对即可识别。
   * 失败或长度不足时返回空串。
   */
  static async fetchCertFingerprintTail(): Promise<string> {
    try {
      const flags: number = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_SIGNATURE_INFO;
      const info: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(flags);
      const sig: bundleManager.SignatureInfo | undefined = info.signatureInfo;
      const fp: string = sig ? sig.fingerprint : '';
      if (fp.length >= 8) {
        const tail: string = fp.substring(fp.length - 8);
        hilog.info(DOMAIN, TAG, '签名指纹读取成功，尾 8 位：%{public}s', tail);
        return tail;
      }
      return '';
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, TAG, '签名指纹读取失败：%{public}s', msg);
      return '';
    }
  }

  /** 是否为云端构建（GitHub Actions 产物才有可跳转的构建记录页） */
  static hasCloudBuild(): boolean {
    return BuildInfo.RUN_ID.length > 0;
  }

  /**
   * 构建信息副标题文案。
   * 云端构建显示 Build 编号 · commit 前 7 位 · 指纹尾 8 位；
   * 本地构建显示"本地构建"前缀（指纹仍有效，对应调试证书，与 README 公布的发布指纹不同属正常）。
   */
  static buildInfoDisplay(certFingerprintTail: string): string {
    const parts: string[] = [];
    if (BuildInfo.COMMIT_SHA.length >= 7) {
      parts.push(BuildInfo.COMMIT_SHA.substring(0, 7));
    }
    if (certFingerprintTail.length > 0) {
      parts.push(tr($r('app.string.appinfosvc_fingerprint_abbrev'), certFingerprintTail));
    }
    if (AppInfoService.hasCloudBuild()) {
      return `Build #${BuildInfo.RUN_NUMBER} · ${parts.join(' · ')}`;
    }
    return tr($r('app.string.appinfosvc_local_build')) +
      (parts.length > 0 ? ' · ' + parts.join(' · ') : '');
  }

  /**
   * 组装「点击复制版本信息」完整多行文本（含版本 + 构建溯源 + 签名指纹）。
   * 便于反馈问题时一次性提供完整证据链。
   */
  static buildVersionClipboardText(
    versionName: string,
    versionCode: number,
    certFingerprintTail: string
  ): string {
    const lines: string[] = [`TimelyNotify ${versionName} (${versionCode})`];
    if (AppInfoService.hasCloudBuild()) {
      lines.push(tr($r('app.string.appinfosvc_clip_cloud_build'), BuildInfo.RUN_NUMBER, BuildInfo.RUN_ID));
    } else {
      lines.push(tr($r('app.string.appinfosvc_clip_local_build')));
    }
    if (BuildInfo.COMMIT_SHA.length > 0) {
      lines.push(tr($r('app.string.appinfosvc_clip_commit'), BuildInfo.COMMIT_SHA));
    }
    if (certFingerprintTail.length > 0) {
      lines.push(tr($r('app.string.appinfosvc_clip_fingerprint'), certFingerprintTail));
    }
    return lines.join('\n');
  }

  /** 云端构建记录页 URL（GitHub Actions /actions/runs/{RUN_ID}）；本地构建不应跳转 */
  static buildRunUrl(): string {
    return `${SOURCE_CODE_URL}/actions/runs/${BuildInfo.RUN_ID}`;
  }
}
