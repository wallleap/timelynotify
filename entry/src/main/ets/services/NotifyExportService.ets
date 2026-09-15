import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NotifyMessage } from '../model/NotifyMessage';
import { NotifyMessageService } from './NotifyMessageService';
import { ServerManager } from './ServerManager';
import { DOMAIN } from '../common/Constant';

const EXPORT_TAG: string = 'NotifyExportSvc';

/** 导出文件中消息 extras 的显式类型，满足 ArkTS 对对象字面量的约束。 */
class NotifyExportExtras {
  device_key: string = '';
  subtitle: string = '';
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
  // 写入的消息条数（成功时 > 0）
  count: number = 0;
  // 服务端流式返回是否被截断（数据可能不完整）
  truncated: boolean = false;
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
    const raw: NotifyExportMessage[] = selected.map((message: NotifyMessage) => NotifyExportService.toRaw(message, deviceKey));
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [`timelynotify_selected_${NotifyExportService.fileTime(new Date())}.txt`];
    options.fileSuffixChoices = ['文档|.txt'];
    const uris: string[] = await new picker.DocumentViewPicker(context).save(options);
    if (uris.length === 0) {
      return 0;
    }
    const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
    try {
      fileIo.writeSync(file.fd, JSON.stringify(raw, null, 2));
    } finally {
      fileIo.closeSync(file);
    }
    return selected.length;
  }

  /**
   * 全量导出当前设备所有消息为 txt 文件（JSON 数组格式，2 空格缩进）。
   * 完整流程：
   *  1. 调 NotifyMessageService.exportAllMessages 全量拉取（limit=-1 服务端流式返回）
   *  2. DocumentViewPicker 拉起系统保存对话框（无需权限），用户选择位置后写入 txt
   *  3. 返回 ExportAllResult 供 UI 层展示 Toast
   *
   * @param context UIAbilityContext（DocumentViewPicker 需要）
   * @returns ExportAllResult：ok / count / truncated / cancelled / errorMsg
   */
  static async exportAll(context: common.UIAbilityContext): Promise<ExportAllResult> {
    const result: ExportAllResult = new ExportAllResult();
    try {
      const pulled = await NotifyMessageService.getInstance().exportAllMessages(null);
      if (!pulled.ok) {
        result.errorMsg = pulled.errorMsg.length > 0 ? pulled.errorMsg : '导出失败';
        return result;
      }
      // 纯 JSON 数组文本（2 空格缩进便于阅读，整体仍是合法 JSON）
      const text: string = JSON.stringify(pulled.rawMessages, null, 2);

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

      // Picker 返回的 URI 需以 READ_WRITE 模式打开后写入
      const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
      try {
        fileIo.writeSync(file.fd, text);
      } finally {
        fileIo.closeSync(file);
      }

      result.ok = true;
      result.count = pulled.rawMessages.length;
      result.truncated = pulled.truncated;
      hilog.info(DOMAIN, EXPORT_TAG, '消息导出完成：count=%{public}d truncated=%{public}s',
        result.count, String(result.truncated));
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      hilog.warn(DOMAIN, EXPORT_TAG, '导出消息失败：%{public}s', msg);
      result.errorMsg = '导出失败';
    }
    return result;
  }

  private static fileTime(date: Date): string {
    const pad = (value: number): string => value < 10 ? `0${value}` : String(value);
    return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}_${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`;
  }

  private static toRaw(message: NotifyMessage, deviceKey: string): NotifyExportMessage {
    const raw: NotifyExportMessage = new NotifyExportMessage();
    raw.id = message.id;
    raw.appid = message.appid;
    raw.title = message.title;
    raw.message = message.body;
    raw.priority = message.priority;
    raw.date = message.date.length > 0 ? message.date : message.createdAt;
    raw.extras.device_key = deviceKey;
    if (message.subtitle.length > 0) {
      raw.extras.subtitle = message.subtitle;
    }
    return raw;
  }
}
