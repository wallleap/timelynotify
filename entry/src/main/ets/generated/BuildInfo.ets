/**
 * 构建溯源信息（自动生成文件 —— 请勿手动修改）
 *
 * 生成时机：
 * - CI（GitHub Actions）：release.yml 在 hvigor 构建前用真实构建上下文覆写本文件
 * - 本地构建：bin/build 在 hvigor 构建前写入本地构建信息，构建后通过 trap 还原
 * - 仓库中提交的是默认占位值（local），保证 DevEco Studio 直接构建也能编译通过
 *
 * 用途（防伪校验）：
 * 「我的 → 关于 → 构建信息」行展示 Build 编号 / commit / 签名指纹尾串；
 * 用户点击后打开云端构建记录页比对，伪造包无法在官方仓库创建对应构建记录。
 */
export class BuildInfo {
  /** 构建来源：github-actions / local */
  static readonly BUILD_HOST: string = 'local';
  /** GitHub Actions Run ID（云端构建记录页 /actions/runs/{RUN_ID}）；本地构建为空串 */
  static readonly RUN_ID: string = '';
  /** GitHub Actions Run 编号（页面展示用） */
  static readonly RUN_NUMBER: string = '';
  /** 构建对应的 commit SHA（完整 40 位） */
  static readonly COMMIT_SHA: string = '';
  /** 构建时间（UTC，ISO 8601 格式） */
  static readonly BUILD_TIME: string = '';
}
