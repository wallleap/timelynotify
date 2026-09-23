import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NotifyMessage } from '../model/NotifyMessage';
import { MessageCacheStore } from './MessageCacheStore';
import { ServerManager } from './ServerManager';
import { DOMAIN } from '../common/Constant';

const EXPORT_TAG: string = 'NotifyExportSvc';

/** 导出文件中通知 extras 的显式类型，满足 ArkTS 对对象字面量的约束。 */
class NotifyExportExtras {
  device_key: string = '';
  subtitle: string = '';
  icon: string = '';
  image: string = '';
  group: string = '';
  inboxcontent: string[] = [];
  ciphertext: string = '';
  iv: string = '';
  isarchive: string = '1';
  expires_at: number = 0;
  // 点击跳转 URL（对应通知 extras.url）
  url: string = '';
}

/** 导出文件中单条通知的显式结构。 */
class NotifyExportMessage {
  id: number = 0;
  appid: number = 0;
  title: string = '';
  message: string = '';
  priority: number = 0;
  date: string = '';
  extras: NotifyExportExtras = new NotifyExportExtras();
}

/** 全量导出结果：UI 层据此展示 Toast。 */
export class ExportAllResult {
  // 是否成功写入文件
  ok: boolean = false;
  // 写入的通知条数（成功时 > 0）
  count: number = 0;
  // 用户在系统保存对话框中取消（静默结束，不弹 Toast）
  cancelled: boolean = false;
  // 失败时的错误文案（UI 层展示）
  errorMsg: string = '';
}

/** 选中通知的系统文件导出服务，保持页面只负责触发与提示。 */
export class NotifyExportService {
  static async exportSelected(context: common.UIAbilityContext, messages: NotifyMessage[], selectedIds: number[]): Promise<number> {
    await ServerManager.getInstance().ensureLoaded();
    const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
    if (!deviceKey || deviceKey.length === 0) {
      return -1;
    }
    const ids: Set<number> = new Set<number>(selectedIds);
    const selected: NotifyMessage[] = messages.filter((message: NotifyMessage) => ids.has(message.id));
    if (selected.length === 0) {
      return 0;
    }
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [`timelynotify_selected_${NotifyExportService.fileTime(new Date())}.txt`];
    options.fileSuffixChoices = ['文档|.txt'];
    const uris: string[] = await new picker.DocumentViewPicker(context).save(options);
    if (uris.length === 0) {
      return 0;
    }
    // fileIo.openSync/writeSync/closeSync 均可能抛异常（URI 无效 / 权限缺失 / IO 错误），
    // 用 try/catch/finally 三段处理：打开失败直接返回；写入失败关闭后返回；最终确保 fd 关闭
    let file: fileIo.File;
    try {
      file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, EXPORT_TAG, '导出文件打开失败：%{public}s', msg);
      return 0;
    }
    try {
      fileIo.writeSync(file.fd, NotifyExportService.serializeMessages(selected, deviceKey));
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, EXPORT_TAG, '导出文件写入失败：%{public}s', msg);
      return 0;
    } finally {
      try {
        fileIo.closeSync(file);
      } catch (_ignore) {
        // 忽略关闭失败（fd 已无效或已关闭）
      }
    }
    return selected.length;
  }

  /**
   * 全量导出当前服务器本地保存的通知为 txt 文件（JSON 数组格式，2 空格缩进）。
   * 完整流程：
   *  1. 从本地数据库读取当前 device_key 全部未过期通知，不受列表分页限制
   *  2. DocumentViewPicker 拉起系统保存对话框（无需权限），用户选择位置后写入 txt
   *  3. 返回 ExportAllResult 供 UI 层展示 Toast
   *
   * @param context UIAbilityContext（DocumentViewPicker 需要）
   * @returns ExportAllResult：ok / count / cancelled / errorMsg
   */
  static async exportAll(context: common.UIAbilityContext): Promise<ExportAllResult> {
    const result: ExportAllResult = new ExportAllResult();
    try {
      await ServerManager.getInstance().ensureLoaded();
      const deviceKey: string = await ServerManager.getInstance().getCurrentDeviceKey(null);
      if (deviceKey.length === 0) {
        result.errorMsg = '设备未注册，无法导出';
        return result;
      }
      const messages: NotifyMessage[] | null = await MessageCacheStore.loadAllForExport(deviceKey);
      if (messages === null) {
        result.errorMsg = '读取本地通知失败';
        return result;
      }
      if (messages.length === 0) {
        result.errorMsg = '暂无可导出的通知';
        return result;
      }
      const text: string = NotifyExportService.serializeMessages(messages, deviceKey);

      // 系统保存对话框：预设文件名 + txt 过滤；Picker 保存无需申请权限
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [`timelynotify_export_${NotifyExportService.fileTime(new Date())}.txt`];
      saveOptions.fileSuffixChoices = ['文档|.txt'];
      const docPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await docPicker.save(saveOptions);
      if (uris.length === 0) {
        result.cancelled = true;
        return result;
      }

      // Picker 返回的 URI 需以 READ_WRITE 模式打开后写入。
      // openSync/writeSync/closeSync 均可能抛异常，统一走外层 try/catch；
      // closeSync 在 finally 中再包一层 try，避免关闭失败掩盖原始错误
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
      try {
        fileIo.writeSync(file.fd, text);
      } finally {
        try {
          fileIo.closeSync(file);
        } catch (_ignore) {
          // 忽略关闭失败（fd 已无效或已关闭）
        }
      }

      result.ok = true;
      result.count = messages.length;
      hilog.info(DOMAIN, EXPORT_TAG, '通知导出完成：count=%{public}d', result.count);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, EXPORT_TAG, '导出通知失败：%{public}s', msg);
      result.errorMsg = '导出失败';
    }
    return result;
  }

  private static fileTime(date: Date): string {
    const pad = (value: number): string => value < 10 ? `0${value}` : String(value);
    return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}_${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`;
  }

  /** 将本地通知转换为兼容既有 Gotify 导出格式的 JSON 数组。 */
  static serializeMessages(messages: NotifyMessage[], deviceKey: string): string {
    const raw: NotifyExportMessage[] = messages.map((message: NotifyMessage) =>
      NotifyExportService.toRaw(message, deviceKey));
    return JSON.stringify(raw, null, 2);
  }

  private static toRaw(message: NotifyMessage, deviceKey: string): NotifyExportMessage {
    const raw: NotifyExportMessage = new NotifyExportMessage();
    raw.id = message.id;
    raw.appid = message.appid;
    raw.title = message.title;
    raw.message = message.body;
    raw.priority = message.priority;
    raw.date = message.date.length > 0 ? message.date : message.createdAt;
    raw.extras.device_key = message.deviceKey.length > 0 ? message.deviceKey : deviceKey;
    raw.extras.icon = message.icon;
    raw.extras.image = message.image;
    raw.extras.group = message.group;
    raw.extras.inboxcontent = message.inboxContent;
    raw.extras.ciphertext = message.ciphertext;
    raw.extras.iv = message.iv;
    raw.extras.isarchive = message.archive ? '1' : '0';
    raw.extras.expires_at = message.expiresAt;
    if (message.subtitle.length > 0) {
      raw.extras.subtitle = message.subtitle;
    }
    if (message.url.length > 0) {
      raw.extras.url = message.url;
    }
    return raw;
  }
}
