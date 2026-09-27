import { NotifyMessage } from '../model/NotifyMessage';

/** 远端 id 只在一份历史数据库内唯一；本地用实例命名空间隔离不同数据库。 */
export function notifySourceKey(instanceId: string, serverId: string, deviceKey: string): string {
  const namespace: string = instanceId.length > 0 ? `db:${instanceId}` : `server:${serverId}`;
  return JSON.stringify([namespace, deviceKey]);
}

/** 本地通知身份；用字符串避免把服务器的数字 id 当作全局唯一值。 */
export function notifyIdentity(message: NotifyMessage): string {
  return JSON.stringify([message.deviceKey, message.id]);
}

/** 判断本地历史键是否属于点击通知给出的数据库实例，不猜测旧版裸 device_key 的来源。 */
export function belongsToPushInstance(sourceKey: string, instanceId: string): boolean {
  if (!instanceId) {
    return false;
  }
  try {
    const parsed: Object = JSON.parse(sourceKey);
    return parsed instanceof Array && parsed.length === 2 && parsed[0] === `db:${instanceId}` &&
      typeof parsed[1] === 'string';
  } catch (_ignore) {
    return false;
  }
}

/** 导出时还原用户可用的原始设备 Key，避免将内部历史命名空间写进 extras。 */
export function originalDeviceKey(sourceKey: string): string {
  if (!sourceKey.startsWith('["db:') && !sourceKey.startsWith('["server:')) {
    return sourceKey;
  }
  try {
    const parsed: Object = JSON.parse(sourceKey);
    if (parsed instanceof Array && parsed.length === 2 && typeof parsed[1] === 'string') {
      return parsed[1] as string;
    }
  } catch (_ignore) {
  }
  return sourceKey;
}

/** 与本地跨服务器分页 SQL 相同的全序（新到旧）。 */
export function compareNotifyOrder(a: NotifyMessage, b: NotifyMessage): number {
  if (a.timestamp !== b.timestamp) {
    return b.timestamp - a.timestamp;
  }
  if (a.id !== b.id) {
    return b.id - a.id;
  }
  return b.deviceKey.localeCompare(a.deviceKey);
}
