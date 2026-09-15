import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { NotifyMessage } from '../model/NotifyMessage';
import { ServerManager } from './ServerManager';

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
    const raw: Object[] = selected.map((message: NotifyMessage) => NotifyExportService.toRaw(message, deviceKey));
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

  private static fileTime(date: Date): string {
    const pad = (value: number): string => value < 10 ? `0${value}` : String(value);
    return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}_${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`;
  }

  private static toRaw(message: NotifyMessage, deviceKey: string): Object {
    const extras: Record<string, Object> = { 'device_key': deviceKey };
    if (message.subtitle.length > 0) {
      extras['subtitle'] = message.subtitle;
    }
    return { 'id': message.id, 'appid': message.appid, 'title': message.title, 'message': message.body,
      'priority': message.priority, 'date': message.date.length > 0 ? message.date : message.createdAt,
      'extras': extras as Object } as Object;
  }
}
