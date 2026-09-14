import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContextStore } from '../common/AppContextStore';
import { DOMAIN } from '../common/Constant';
import { NotifyMessage } from '../model/NotifyMessage';

const TAG: string = 'MsgCache';
const DB_NAME: string = 'timelynotify_msg.db';
const TABLE_MSG: string = 'notify_message';
const TABLE_META: string = 'sync_meta';

// 消息表：按 (device_key, id) 主键；timestamp 索引支持按时间倒序分页
const SQL_CREATE_MSG: string =
  `CREATE TABLE IF NOT EXISTS ${TABLE_MSG} (` +
  'device_key TEXT NOT NULL, ' +
  'id INTEGER NOT NULL, ' +
  'appid INTEGER NOT NULL DEFAULT 0, ' +
  'title TEXT NOT NULL DEFAULT \'\', ' +
  'body TEXT NOT NULL DEFAULT \'\', ' +
  'subtitle TEXT NOT NULL DEFAULT \'\', ' +
  'priority INTEGER NOT NULL DEFAULT 0, ' +
  'date TEXT NOT NULL DEFAULT \'\', ' +
  'created_at TEXT NOT NULL DEFAULT \'\', ' +
  'timestamp INTEGER NOT NULL DEFAULT 0, ' +
  'image TEXT NOT NULL DEFAULT \'\', ' +
  // inboxContent 序列化为 JSON 字符串存储
  'inbox_content TEXT NOT NULL DEFAULT \'\', ' +
  // 通知分组标识（对应 NotifyMessage.group；不能用 group 命名，SQL 保留字）
  'group_key TEXT NOT NULL DEFAULT \'\', ' +
  'PRIMARY KEY (device_key, id)' +
  ')';

const SQL_CREATE_MSG_INDEX: string =
  `CREATE INDEX IF NOT EXISTS idx_msg_dev_ts ON ${TABLE_MSG}(device_key, timestamp DESC)`;

// 同步元信息：每设备的最大已同步消息 id 与删除流水游标
const SQL_CREATE_META: string =
  `CREATE TABLE IF NOT EXISTS ${TABLE_META} (` +
  'device_key TEXT PRIMARY KEY, ' +
  'max_id INTEGER NOT NULL DEFAULT 0, ' +
  'del_cursor INTEGER NOT NULL DEFAULT 0, ' +
  'last_sync_at INTEGER NOT NULL DEFAULT 0' +
  ')';

/** 同步元信息：maxId=已同步到本地的最大消息 id；delCursor=删除流水游标 */
export class SyncMeta {
  maxId: number = 0;
  delCursor: number = 0;
}

function formatError(err: Object): string {
  if (err instanceof Error) {
    return err.message;
  }
  return String(err);
}

// 将 NotifyMessage 转为 RDB 行（ValuesBucket）
function toBucket(deviceKey: string, m: NotifyMessage): relationalStore.ValuesBucket {
  const bucket: relationalStore.ValuesBucket = {
    'device_key': deviceKey,
    'id': m.id,
    'appid': m.appid,
    'title': m.title,
    'body': m.body,
    'subtitle': m.subtitle,
    'priority': m.priority,
    'date': m.date,
    'created_at': m.createdAt,
    'timestamp': m.timestamp,
    'image': m.image,
    'inbox_content': JSON.stringify(m.inboxContent),
    'group_key': m.group,
  };
  return bucket;
}

// 从 ResultSet 当前行构造 NotifyMessage
function rowToMessage(rs: relationalStore.ResultSet): NotifyMessage {
  const m: NotifyMessage = new NotifyMessage();
  m.id = rs.getLong(rs.getColumnIndex('id'));
  m.appid = rs.getLong(rs.getColumnIndex('appid'));
  m.title = rs.getString(rs.getColumnIndex('title'));
  m.body = rs.getString(rs.getColumnIndex('body'));
  m.subtitle = rs.getString(rs.getColumnIndex('subtitle'));
  m.priority = rs.getLong(rs.getColumnIndex('priority'));
  m.date = rs.getString(rs.getColumnIndex('date'));
  m.createdAt = rs.getString(rs.getColumnIndex('created_at'));
  m.timestamp = rs.getLong(rs.getColumnIndex('timestamp'));
  m.image = rs.getString(rs.getColumnIndex('image'));
  m.group = rs.getString(rs.getColumnIndex('group_key'));
  const inboxStr: string = rs.getString(rs.getColumnIndex('inbox_content'));
  if (inboxStr && inboxStr.length > 0) {
    try {
      const parsed: Object = JSON.parse(inboxStr);
      if (parsed instanceof Array) {
        const parsedArr: Object[] = parsed as Object[];
        const arr: string[] = [];
        for (let i = 0; i < parsedArr.length; i++) {
          if (typeof parsedArr[i] === 'string') {
            arr.push(parsedArr[i] as string);
          }
        }
        m.inboxContent = arr;
      }
    } catch (_ignore) {
      m.inboxContent = [];
    }
  }
  return m;
}

/**
 * 消息本地缓存（关系型数据库 SQLite）。
 * 按 device_key 隔离，缓存优先于网络渲染，配合服务端 after/deletedSince 协议增量同步。
 * 单例 + 静态方法风格，与项目其它服务层一致。
 */
export class MessageCacheStore {
  private static store: relationalStore.RdbStore | null = null;

  /**
   * 旧库结构迁移。
   * v1 建表时漏了分组标识列，导致从缓存读出的消息 group 恒为空、列表分组失效。
   * 检测到 group_key 缺失时：ADD COLUMN 补列，并清空消息与同步元信息，
   * 让下次同步走 after=0 全量重新播种（增量同步无法回填旧行的 group）。
   */
  private static async migrateSchema(db: relationalStore.RdbStore): Promise<void> {
    try {
      const rs: relationalStore.ResultSet =
        await db.querySql(`PRAGMA table_info(${TABLE_MSG})`);
      let hasGroupKey: boolean = false;
      if (rs.goToFirstRow()) {
        const nameIndex: number = rs.getColumnIndex('name');
        do {
          if (rs.getString(nameIndex) === 'group_key') {
            hasGroupKey = true;
            break;
          }
        } while (rs.goToNextRow());
      }
      rs.close();
      if (hasGroupKey) {
        return;
      }
      hilog.info(DOMAIN, TAG, '迁移：notify_message 补充 group_key 列并清空旧缓存');
      await db.executeSql(
        `ALTER TABLE ${TABLE_MSG} ADD COLUMN group_key TEXT NOT NULL DEFAULT ''`);
      // 旧行 group 无法回填，作废本地缓存重新播种（元信息一并清空，等价于一次 forceFull）
      await db.executeSql(`DELETE FROM ${TABLE_MSG}`);
      await db.executeSql(`DELETE FROM ${TABLE_META}`);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'migrateSchema 失败：%{public}s', formatError(err));
    }
  }

  private static async getStore(): Promise<relationalStore.RdbStore | null> {
    if (MessageCacheStore.store) {
      return MessageCacheStore.store;
    }
    const ctx = AppContextStore.getInstance().getContext();
    if (!ctx) {
      hilog.error(DOMAIN, TAG, 'getStore 无法获取 context');
      return null;
    }
    try {
      const config: relationalStore.StoreConfig = {
        name: DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1,
      };
      const db: relationalStore.RdbStore = await relationalStore.getRdbStore(ctx, config);
      await db.executeSql(SQL_CREATE_MSG);
      await db.executeSql(SQL_CREATE_MSG_INDEX);
      await db.executeSql(SQL_CREATE_META);
      await MessageCacheStore.migrateSchema(db);
      MessageCacheStore.store = db;
      return db;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'getRdbStore 失败：%{public}s', formatError(err));
      return null;
    }
  }

  // 加载某设备最新 N 条消息（按 timestamp 倒序，新→旧），用于冷启动首屏
  static async loadLatest(deviceKey: string, limit: number): Promise<NotifyMessage[]> {
    const db = await MessageCacheStore.getStore();
    if (!db) {
      return [];
    }
    const list: NotifyMessage[] = [];
    try {
      const sql: string =
        `SELECT * FROM ${TABLE_MSG} WHERE device_key=? ORDER BY timestamp DESC, id DESC LIMIT ?`;
      const rs: relationalStore.ResultSet = await db.querySql(sql, [deviceKey, limit]);
      if (rs.goToFirstRow()) {
        do {
          list.push(rowToMessage(rs));
        } while (rs.goToNextRow());
      }
      rs.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'loadLatest 失败：%{public}s', formatError(err));
    }
    return list;
  }

  // 加载某设备比 beforeId 更老的 N 条消息（id < beforeId，按 id 倒序），用于触底加载
  static async loadOlder(deviceKey: string, beforeId: number, limit: number): Promise<NotifyMessage[]> {
    const db = await MessageCacheStore.getStore();
    if (!db || beforeId <= 0) {
      return [];
    }
    const list: NotifyMessage[] = [];
    try {
      const sql: string =
        `SELECT * FROM ${TABLE_MSG} WHERE device_key=? AND id < ? ORDER BY id DESC LIMIT ?`;
      const rs: relationalStore.ResultSet = await db.querySql(sql, [deviceKey, beforeId, limit]);
      if (rs.goToFirstRow()) {
        do {
          list.push(rowToMessage(rs));
        } while (rs.goToNextRow());
      }
      rs.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'loadOlder 失败：%{public}s', formatError(err));
    }
    return list;
  }

  // 批量写入消息（主键冲突时替换，upsert 语义）
  // 注：batchInsert 不支持冲突解决参数，故用 insert 循环 + ON_CONFLICT_REPLACE
  static async upsertMessages(deviceKey: string, messages: NotifyMessage[]): Promise<void> {
    if (!messages || messages.length === 0) {
      return;
    }
    const db = await MessageCacheStore.getStore();
    if (!db) {
      return;
    }
    try {
      for (let i = 0; i < messages.length; i++) {
        const bucket: relationalStore.ValuesBucket = toBucket(deviceKey, messages[i]);
        await db.insert(TABLE_MSG, bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'upsertMessages 失败：%{public}s', formatError(err));
    }
  }

  // 按消息 id 列表删除（跨端删除事件 / 本端删除后落库）
  static async deleteByIds(deviceKey: string, ids: number[]): Promise<void> {
    if (!ids || ids.length === 0) {
      return;
    }
    const db = await MessageCacheStore.getStore();
    if (!db) {
      return;
    }
    try {
      const placeholders: string[] = [];
      for (let i = 0; i < ids.length; i++) {
        placeholders.push('?');
      }
      const args: Array<number | string> = [deviceKey];
      for (let i = 0; i < ids.length; i++) {
        args.push(ids[i]);
      }
      const sql: string =
        `DELETE FROM ${TABLE_MSG} WHERE device_key=? AND id IN (${placeholders.join(',')})`;
      await db.executeSql(sql, args);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'deleteByIds 失败：%{public}s', formatError(err));
    }
  }

  // 清空本地该设备 id <= ceiling 的所有消息（服务端清空全部的 purge 语义）
  static async purgeBefore(deviceKey: string, ceiling: number): Promise<void> {
    const db = await MessageCacheStore.getStore();
    if (!db) {
      return;
    }
    try {
      const sql: string = `DELETE FROM ${TABLE_MSG} WHERE device_key=? AND id <= ?`;
      await db.executeSql(sql, [deviceKey, ceiling]);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'purgeBefore 失败：%{public}s', formatError(err));
    }
  }

  // 清空某设备的全部缓存与元信息（reset 重建 / 切换设备清理）
  static async clearDevice(deviceKey: string): Promise<void> {
    const db = await MessageCacheStore.getStore();
    if (!db) {
      return;
    }
    try {
      await db.executeSql(`DELETE FROM ${TABLE_MSG} WHERE device_key=?`, [deviceKey]);
      await db.executeSql(`DELETE FROM ${TABLE_META} WHERE device_key=?`, [deviceKey]);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'clearDevice 失败：%{public}s', formatError(err));
    }
  }

  // 读取某设备的同步元信息（不存在则返回默认 0）
  static async getMeta(deviceKey: string): Promise<SyncMeta> {
    const meta: SyncMeta = new SyncMeta();
    const db = await MessageCacheStore.getStore();
    if (!db) {
      return meta;
    }
    try {
      const sql: string = `SELECT max_id, del_cursor FROM ${TABLE_META} WHERE device_key=?`;
      const rs: relationalStore.ResultSet = await db.querySql(sql, [deviceKey]);
      if (rs.goToFirstRow()) {
        meta.maxId = rs.getLong(rs.getColumnIndex('max_id'));
        meta.delCursor = rs.getLong(rs.getColumnIndex('del_cursor'));
      }
      rs.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'getMeta 失败：%{public}s', formatError(err));
    }
    return meta;
  }

  // 写入某设备的同步元信息（maxId/delCursor）；已存在则替换
  static async saveMeta(deviceKey: string, maxId: number, delCursor: number): Promise<void> {
    const db = await MessageCacheStore.getStore();
    if (!db) {
      return;
    }
    try {
      const bucket: relationalStore.ValuesBucket = {
        'device_key': deviceKey,
        'max_id': maxId,
        'del_cursor': delCursor,
        'last_sync_at': Date.now(),
      };
      await db.insert(TABLE_META, bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'saveMeta 失败：%{public}s', formatError(err));
    }
  }

  // 获取某设备本地缓存中的最大消息 id（用于初始同步基线）
  static async getMaxId(deviceKey: string): Promise<number> {
    const db = await MessageCacheStore.getStore();
    if (!db) {
      return 0;
    }
    try {
      const sql: string = `SELECT COALESCE(MAX(id), 0) AS max_id FROM ${TABLE_MSG} WHERE device_key=?`;
      const rs: relationalStore.ResultSet = await db.querySql(sql, [deviceKey]);
      let maxId: number = 0;
      if (rs.goToFirstRow()) {
        maxId = rs.getLong(rs.getColumnIndex('max_id'));
      }
      rs.close();
      return maxId;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'getMaxId 失败：%{public}s', formatError(err));
      return 0;
    }
  }
}
