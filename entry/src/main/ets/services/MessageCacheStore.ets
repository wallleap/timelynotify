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
  'icon TEXT NOT NULL DEFAULT \'\', ' +
  'image TEXT NOT NULL DEFAULT \'\', ' +
  // inboxContent 序列化为 JSON 字符串存储
  'inbox_content TEXT NOT NULL DEFAULT \'\', ' +
  // 通知分组标识（对应 NotifyMessage.group；不能用 group 命名，SQL 保留字）
  'group_key TEXT NOT NULL DEFAULT \'\', ' +
  // 点击跳转 URL（对应 NotifyMessage.url，来自 extras.url）
  'url TEXT NOT NULL DEFAULT \'\', ' +
  // 保存加密标记与原始密文，便于远程历史删除后仍可在本地更换 Key 重新解密。
  'encrypted INTEGER NOT NULL DEFAULT 0, ' +
  'ciphertext TEXT NOT NULL DEFAULT \'\', ' +
  'iv TEXT NOT NULL DEFAULT \'\', ' +
  // Bark 归档策略及 ttl 的绝对过期时间；旧记录默认继续保留且永不过期。
  'archive INTEGER NOT NULL DEFAULT 1, ' +
  'expires_at INTEGER NOT NULL DEFAULT 0, ' +
  'PRIMARY KEY (device_key, id)' +
  ')';

const SQL_CREATE_MSG_INDEX: string =
  `CREATE INDEX IF NOT EXISTS idx_msg_dev_ts ON ${TABLE_MSG}(device_key, timestamp DESC)`;

// 同步元信息：每设备的最大消息 id、删除流水游标与一次性历史播种进度
const SQL_CREATE_META: string =
  `CREATE TABLE IF NOT EXISTS ${TABLE_META} (` +
  'device_key TEXT PRIMARY KEY, ' +
  'max_id INTEGER NOT NULL DEFAULT 0, ' +
  'del_cursor INTEGER NOT NULL DEFAULT 0, ' +
  'history_cursor INTEGER NOT NULL DEFAULT 0, ' +
  'history_complete INTEGER NOT NULL DEFAULT 0, ' +
  'last_sync_at INTEGER NOT NULL DEFAULT 0' +
  ')';

/**
 * 同步元信息：
 * - maxId：已写入本地的最大消息 id，历史播种完成后用于增量同步；
 * - delCursor：服务端删除流水游标；
 * - historyCursor：首次历史播种已安全落盘的最后一条 id；
 * - historyComplete：服务端明确返回历史末尾后才置为 true。
 */
export class SyncMeta {
  maxId: number = 0;
  delCursor: number = 0;
  historyCursor: number = 0;
  historyComplete: boolean = false;
}

/** 分组加载结果：合并后的消息列表 + 每个 group_key 的真实总数 */
export interface GroupedLoadResult {
  messages: NotifyMessage[];
  totals: Map<string, number>;
}

/** (deviceKey, id) 对，用于跨服务器精确删除（不同服务器 id 空间独立） */
export interface DeviceIdPair {
  deviceKey: string;
  id: number;
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
    'icon': m.icon,
    'image': m.image,
    'inbox_content': JSON.stringify(m.inboxContent),
    'group_key': m.group,
    'url': m.url,
    'encrypted': m.encrypted ? 1 : 0,
    'ciphertext': m.ciphertext,
    'iv': m.iv,
    'archive': m.archive ? 1 : 0,
    'expires_at': m.expiresAt,
  };
  return bucket;
}

// 从 ResultSet 当前行构造 NotifyMessage
// ResultSet.getXxx / getColumnIndex 等方法可能抛异常（列缺失/类型不匹配/游标失效），
// 包裹整个读取过程：异常时记录日志并抛出，让调用方感知数据损坏而非静默返回半截对象
function rowToMessage(rs: relationalStore.ResultSet): NotifyMessage {
  const m: NotifyMessage = new NotifyMessage();
  try {
    m.id = rs.getLong(rs.getColumnIndex('id'));
    m.appid = rs.getLong(rs.getColumnIndex('appid'));
    m.title = rs.getString(rs.getColumnIndex('title'));
    m.body = rs.getString(rs.getColumnIndex('body'));
    m.subtitle = rs.getString(rs.getColumnIndex('subtitle'));
    m.priority = rs.getLong(rs.getColumnIndex('priority'));
    m.date = rs.getString(rs.getColumnIndex('date'));
    m.createdAt = rs.getString(rs.getColumnIndex('created_at'));
    m.timestamp = rs.getLong(rs.getColumnIndex('timestamp'));
    m.icon = rs.getString(rs.getColumnIndex('icon'));
    m.image = rs.getString(rs.getColumnIndex('image'));
    m.group = rs.getString(rs.getColumnIndex('group_key'));
    m.url = rs.getString(rs.getColumnIndex('url'));
    m.encrypted = rs.getLong(rs.getColumnIndex('encrypted')) === 1;
    m.ciphertext = rs.getString(rs.getColumnIndex('ciphertext'));
    m.iv = rs.getString(rs.getColumnIndex('iv'));
    m.archive = rs.getLong(rs.getColumnIndex('archive')) === 1;
    m.expiresAt = rs.getLong(rs.getColumnIndex('expires_at'));
    m.deviceKey = rs.getString(rs.getColumnIndex('device_key'));
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
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    hilog.error(DOMAIN, TAG, 'rowToMessage 读取失败：%{public}s', msg);
    // arkts-limited-throw：仅允许 throw Error 实例
    throw err instanceof Error ? err : new Error(msg);
  }
  return m;
}

/**
 * 消息本地缓存（关系型数据库 SQLite）。
 * 按 device_key 隔离，缓存优先于网络渲染；远程通知迁移完成后由本地缓存承载历史展示。
 * 单例 + 静态方法风格，与项目其它服务层一致。
 */
export class MessageCacheStore {
  private static store: relationalStore.RdbStore | null = null;

  /**
   * 旧库结构迁移。
   * v1 建表时漏了分组标识列，导致从缓存读出的消息 group 恒为空、列表分组失效；
   * v2 补充跳转链接 url 列；v3 为同步元信息增加一次性历史播种进度；
   * v4 补充加密状态 encrypted 列，供解密后的消息显示状态标签；
   * v5 补充 ciphertext/iv 列，使远程记录迁移删除后仍可在本地重新解密；
   * v6 补充 archive/expires_at，接入 Bark isArchive 与 ttl，旧记录默认永久保留。
   * v7 拆分 icon/image；旧版 image 实际保存的是远程 icon，迁移到新 icon 列。
   * 检测到缺失列时逐列补齐：
   * - group_key 缺失：旧行分组无法回填，清空消息与元信息，让下次同步走 after=0 全量重新播种；
   * - url 缺失：仅补列即可，旧行本无 url（历史事实），无需清库重播种。
   * - encrypted 缺失：旧行无法判断原始消息是否携带密文，清空消息与元信息后重新播种。
   */
  private static async migrateSchema(db: relationalStore.RdbStore): Promise<void> {
    try {
      const rs: relationalStore.ResultSet =
        await db.querySql(`PRAGMA table_info(${TABLE_MSG})`);
      let hasGroupKey: boolean = false;
      let hasUrl: boolean = false;
      let hasEncrypted: boolean = false;
      let hasCiphertext: boolean = false;
      let hasIv: boolean = false;
      let hasArchive: boolean = false;
      let hasExpiresAt: boolean = false;
      let hasIcon: boolean = false;
      if (rs.goToFirstRow()) {
        const nameIndex: number = rs.getColumnIndex('name');
        do {
          const col: string = rs.getString(nameIndex);
          if (col === 'group_key') {
            hasGroupKey = true;
          } else if (col === 'url') {
            hasUrl = true;
          } else if (col === 'encrypted') {
            hasEncrypted = true;
          } else if (col === 'ciphertext') {
            hasCiphertext = true;
          } else if (col === 'iv') {
            hasIv = true;
          } else if (col === 'archive') {
            hasArchive = true;
          } else if (col === 'expires_at') {
            hasExpiresAt = true;
          } else if (col === 'icon') {
            hasIcon = true;
          }
        } while (rs.goToNextRow());
      }
      rs.close();
      // group_key 缺失：清空本地缓存重新播种（元信息一并清空，等价于一次 forceFull）
      if (!hasGroupKey) {
        hilog.info(DOMAIN, TAG, '迁移：notify_message 补充 group_key 列并清空旧缓存');
        await db.executeSql(
          `ALTER TABLE ${TABLE_MSG} ADD COLUMN group_key TEXT NOT NULL DEFAULT ''`);
        await db.executeSql(`DELETE FROM ${TABLE_MSG}`);
        await db.executeSql(`DELETE FROM ${TABLE_META}`);
      }
      // url 缺失：仅补列，保留已有数据
      if (!hasUrl) {
        hilog.info(DOMAIN, TAG, '迁移：notify_message 补充 url 列');
        await db.executeSql(
          `ALTER TABLE ${TABLE_MSG} ADD COLUMN url TEXT NOT NULL DEFAULT ''`);
      }
      if (!hasEncrypted) {
        hilog.info(DOMAIN, TAG, '迁移：notify_message 补充 encrypted 列并清空旧缓存');
        await db.executeSql(
          `ALTER TABLE ${TABLE_MSG} ADD COLUMN encrypted INTEGER NOT NULL DEFAULT 0`);
        await db.executeSql(`DELETE FROM ${TABLE_MSG}`);
        await db.executeSql(`DELETE FROM ${TABLE_META}`);
      }
      if (!hasCiphertext) {
        hilog.info(DOMAIN, TAG, '迁移：notify_message 补充 ciphertext 列');
        await db.executeSql(
          `ALTER TABLE ${TABLE_MSG} ADD COLUMN ciphertext TEXT NOT NULL DEFAULT ''`);
      }
      if (!hasIv) {
        hilog.info(DOMAIN, TAG, '迁移：notify_message 补充 iv 列');
        await db.executeSql(
          `ALTER TABLE ${TABLE_MSG} ADD COLUMN iv TEXT NOT NULL DEFAULT ''`);
      }
      if (!hasArchive) {
        hilog.info(DOMAIN, TAG, '迁移：notify_message 补充 archive 列');
        await db.executeSql(
          `ALTER TABLE ${TABLE_MSG} ADD COLUMN archive INTEGER NOT NULL DEFAULT 1`);
      }
      if (!hasExpiresAt) {
        hilog.info(DOMAIN, TAG, '迁移：notify_message 补充 expires_at 列');
        await db.executeSql(
          `ALTER TABLE ${TABLE_MSG} ADD COLUMN expires_at INTEGER NOT NULL DEFAULT 0`);
      }
      if (!hasIcon) {
        hilog.info(DOMAIN, TAG, '迁移：拆分 notify_message icon/image 字段');
        await db.executeSql(
          `ALTER TABLE ${TABLE_MSG} ADD COLUMN icon TEXT NOT NULL DEFAULT ''`);
        // 旧客户端把 extras.icon 写入 image；迁移后恢复为 icon，避免被误当作正文大图。
        await db.executeSql(
          `UPDATE ${TABLE_MSG} SET icon=image, image='' WHERE icon='' AND image<>''`);
      }

      // 旧版本的 max_id 只代表“已拉到的最新消息”，不能证明历史已完整。
      // 因此迁移后默认 history_complete=0，保留缓存并从 id=0 补齐一次完整历史。
      const metaRs: relationalStore.ResultSet =
        await db.querySql(`PRAGMA table_info(${TABLE_META})`);
      let hasHistoryCursor: boolean = false;
      let hasHistoryComplete: boolean = false;
      if (metaRs.goToFirstRow()) {
        const nameIndex: number = metaRs.getColumnIndex('name');
        do {
          const col: string = metaRs.getString(nameIndex);
          if (col === 'history_cursor') {
            hasHistoryCursor = true;
          } else if (col === 'history_complete') {
            hasHistoryComplete = true;
          }
        } while (metaRs.goToNextRow());
      }
      metaRs.close();
      if (!hasHistoryCursor) {
        hilog.info(DOMAIN, TAG, '迁移：sync_meta 补充 history_cursor 列');
        await db.executeSql(
          `ALTER TABLE ${TABLE_META} ADD COLUMN history_cursor INTEGER NOT NULL DEFAULT 0`);
      }
      if (!hasHistoryComplete) {
        hilog.info(DOMAIN, TAG, '迁移：sync_meta 补充 history_complete 列');
        await db.executeSql(
          `ALTER TABLE ${TABLE_META} ADD COLUMN history_complete INTEGER NOT NULL DEFAULT 0`);
      }
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

  /**
   * 分组加载：每个 group_key 取最新 perGroupLimit 条，合并按 timestamp DESC 排序。
   * 同时返回每个 group_key 的真实总数，用于徽标显示。
   * 无 group_key（空串）的消息也按 perGroupLimit 截断，作为单条 section 展示。
   */
  static async loadGroupedLatest(deviceKey: string, perGroupLimit: number): Promise<GroupedLoadResult> {
    const db = await MessageCacheStore.getStore();
    const emptyResult: GroupedLoadResult = {
      messages: [] as NotifyMessage[],
      totals: new Map<string, number>(),
    };
    if (!db) {
      return emptyResult;
    }
    try {
      // 1) 查询所有 distinct group_key（含空串代表无分组）
      const keys: string[] = [];
      const rsKeys: relationalStore.ResultSet = await db.querySql(
        `SELECT DISTINCT group_key FROM ${TABLE_MSG} WHERE device_key=?`, [deviceKey]);
      if (rsKeys.goToFirstRow()) {
        const idx: number = rsKeys.getColumnIndex('group_key');
        do {
          keys.push(rsKeys.getString(idx));
        } while (rsKeys.goToNextRow());
      }
      rsKeys.close();
      if (keys.length === 0) {
        return emptyResult;
      }

      // 2) 对每个 group_key 查询最新 perGroupLimit 条 + 总数
      const totals: Map<string, number> = new Map<string, number>();
      const all: NotifyMessage[] = [];
      for (let i = 0; i < keys.length; i++) {
        const gk: string = keys[i];
        // 最新 perGroupLimit 条
        const rs: relationalStore.ResultSet = await db.querySql(
          `SELECT * FROM ${TABLE_MSG} WHERE device_key=? AND group_key=? ` +
          `ORDER BY timestamp DESC, id DESC LIMIT ?`,
          [deviceKey, gk, perGroupLimit]);
        if (rs.goToFirstRow()) {
          do {
            all.push(rowToMessage(rs));
          } while (rs.goToNextRow());
        }
        rs.close();
        // 该 group_key 总数
        const rsCnt: relationalStore.ResultSet = await db.querySql(
          `SELECT COUNT(*) AS cnt FROM ${TABLE_MSG} WHERE device_key=? AND group_key=?`,
          [deviceKey, gk]);
        let cnt: number = 0;
        if (rsCnt.goToFirstRow()) {
          cnt = rsCnt.getLong(rsCnt.getColumnIndex('cnt'));
        }
        rsCnt.close();
        totals.set(gk, cnt);
      }

      // 3) 合并后按 timestamp DESC（新→旧）整体排序
      all.sort((a: NotifyMessage, b: NotifyMessage) => {
        if (b.timestamp !== a.timestamp) {
          return b.timestamp - a.timestamp;
        }
        return b.id - a.id;
      });
      const result: GroupedLoadResult = { messages: all, totals };
      return result;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'loadGroupedLatest 失败：%{public}s', formatError(err));
      return emptyResult;
    }
  }

  /**
   * 加载某 group_key 下比 beforeId 更老的 N 条（id < beforeId，按 id 倒序）。
   * 用于组内"加载更多"按钮。
   */
  static async loadGroupOlder(deviceKey: string, groupKey: string,
    beforeId: number, limit: number): Promise<NotifyMessage[]> {
    const db = await MessageCacheStore.getStore();
    if (!db || beforeId <= 0) {
      return [];
    }
    const list: NotifyMessage[] = [];
    try {
      const sql: string =
        `SELECT * FROM ${TABLE_MSG} WHERE device_key=? AND group_key=? AND id < ? ` +
        `ORDER BY id DESC LIMIT ?`;
      const rs: relationalStore.ResultSet =
        await db.querySql(sql, [deviceKey, groupKey, beforeId, limit]);
      if (rs.goToFirstRow()) {
        do {
          list.push(rowToMessage(rs));
        } while (rs.goToNextRow());
      }
      rs.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'loadGroupOlder 失败：%{public}s', formatError(err));
    }
    return list;
  }

  /**
   * 查询某设备所有 group_key 的真实总数（含空串代表无分组）。
   * 用于增量同步后刷新 groupTotals，而不重拉消息。
   */
  static async getGroupTotals(deviceKey: string): Promise<Map<string, number>> {
    const totals: Map<string, number> = new Map<string, number>();
    const db = await MessageCacheStore.getStore();
    if (!db) {
      return totals;
    }
    try {
      const sql: string =
        `SELECT group_key, COUNT(*) AS cnt FROM ${TABLE_MSG} WHERE device_key=? GROUP BY group_key`;
      const rs: relationalStore.ResultSet = await db.querySql(sql, [deviceKey]);
      if (rs.goToFirstRow()) {
        const keyIdx: number = rs.getColumnIndex('group_key');
        const cntIdx: number = rs.getColumnIndex('cnt');
        do {
          totals.set(rs.getString(keyIdx), rs.getLong(cntIdx));
        } while (rs.goToNextRow());
      }
      rs.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'getGroupTotals 失败：%{public}s', formatError(err));
    }
    return totals;
  }

  // 批量写入消息（主键冲突时替换，upsert 语义）
  // 注：batchInsert 不支持冲突解决参数，故用 insert 循环 + ON_CONFLICT_REPLACE
  static async upsertMessages(deviceKey: string, messages: NotifyMessage[]): Promise<boolean> {
    if (!messages || messages.length === 0) {
      return true;
    }
    const db = await MessageCacheStore.getStore();
    if (!db) {
      return false;
    }
    try {
      const now: number = Date.now();
      for (let i = 0; i < messages.length; i++) {
        const message: NotifyMessage = messages[i];
        if (!message.archive || message.isExpired(now)) {
          // 非归档或已过期消息可能已有旧缓存，必须同步移除以保证重解密后策略生效。
          await db.executeSql(
            `DELETE FROM ${TABLE_MSG} WHERE device_key=? AND id=?`, [deviceKey, message.id]);
          continue;
        }
        const bucket: relationalStore.ValuesBucket = toBucket(deviceKey, message);
        await db.insert(TABLE_MSG, bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      }
      return true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'upsertMessages 失败：%{public}s', formatError(err));
      return false;
    }
  }

  /** 清理所有设备中已经达到 ttl 的本地历史，返回实际删除条数。 */
  static async purgeExpired(now: number = Date.now()): Promise<number> {
    const db = await MessageCacheStore.getStore();
    if (!db) {
      return 0;
    }
    try {
      const rs: relationalStore.ResultSet = await db.querySql(
        `SELECT COUNT(*) AS cnt FROM ${TABLE_MSG} WHERE expires_at>0 AND expires_at<=?`, [now]);
      let count: number = 0;
      if (rs.goToFirstRow()) {
        count = rs.getLong(rs.getColumnIndex('cnt'));
      }
      rs.close();
      if (count > 0) {
        await db.executeSql(
          `DELETE FROM ${TABLE_MSG} WHERE expires_at>0 AND expires_at<=?`, [now]);
      }
      return count;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'purgeExpired 失败：%{public}s', formatError(err));
      return -1;
    }
  }

  /** 读取某设备全部仍保留原始密文的通知，供 Key 或算法变更后在本地重新解密。 */
  static async loadEncryptedMessages(deviceKey: string): Promise<NotifyMessage[]> {
    const db = await MessageCacheStore.getStore();
    const messages: NotifyMessage[] = [];
    if (!db) {
      return messages;
    }
    try {
      const rs: relationalStore.ResultSet = await db.querySql(
        `SELECT * FROM ${TABLE_MSG} WHERE device_key=? AND ciphertext<>'' ORDER BY id ASC`, [deviceKey]);
      if (rs.goToFirstRow()) {
        do {
          messages.push(rowToMessage(rs));
        } while (rs.goToNextRow());
      }
      rs.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'loadEncryptedMessages 失败：%{public}s', formatError(err));
    }
    return messages;
  }

  /** 删除一个或多个设备中指定分组的全部本地通知，返回实际删除条数。 */
  static async deleteGroup(deviceKeys: string[], groupKey: string): Promise<number> {
    const db = await MessageCacheStore.getStore();
    if (!db || deviceKeys.length === 0) {
      return 0;
    }
    try {
      const placeholders: string = deviceKeys.map(() => '?').join(',');
      const args: string[] = deviceKeys.slice();
      args.push(groupKey);
      const where: string = `device_key IN (${placeholders}) AND group_key=?`;
      const rs: relationalStore.ResultSet = await db.querySql(
        `SELECT COUNT(*) AS cnt FROM ${TABLE_MSG} WHERE ${where}`, args);
      let count: number = 0;
      if (rs.goToFirstRow()) {
        count = rs.getLong(rs.getColumnIndex('cnt'));
      }
      rs.close();
      await db.executeSql(`DELETE FROM ${TABLE_MSG} WHERE ${where}`, args);
      return count;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'deleteGroup 失败：%{public}s', formatError(err));
      return -1;
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
      const sql: string =
        `SELECT max_id, del_cursor, history_cursor, history_complete FROM ${TABLE_META} WHERE device_key=?`;
      const rs: relationalStore.ResultSet = await db.querySql(sql, [deviceKey]);
      if (rs.goToFirstRow()) {
        meta.maxId = rs.getLong(rs.getColumnIndex('max_id'));
        meta.delCursor = rs.getLong(rs.getColumnIndex('del_cursor'));
        meta.historyCursor = rs.getLong(rs.getColumnIndex('history_cursor'));
        meta.historyComplete = rs.getLong(rs.getColumnIndex('history_complete')) === 1;
      }
      rs.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'getMeta 失败：%{public}s', formatError(err));
    }
    return meta;
  }

  /**
   * 写入某设备的同步元信息；仅在当前页消息已落库后推进 historyCursor，
   * 从而在应用退出或网络中断后可以安全地从上次成功页继续。
   */
  static async saveMeta(deviceKey: string, maxId: number, delCursor: number,
    historyCursor: number, historyComplete: boolean): Promise<boolean> {
    const db = await MessageCacheStore.getStore();
    if (!db) {
      return false;
    }
    try {
      const bucket: relationalStore.ValuesBucket = {
        'device_key': deviceKey,
        'max_id': maxId,
        'del_cursor': delCursor,
        'history_cursor': historyCursor,
        'history_complete': historyComplete ? 1 : 0,
        'last_sync_at': Date.now(),
      };
      await db.insert(TABLE_META, bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      return true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'saveMeta 失败：%{public}s', formatError(err));
      return false;
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

  /**
   * 跨多个 device_key 分组加载（"全部"视图模式）。
   * 与 loadGroupedLatest 逻辑一致，但 device_key 用 IN (...) 匹配多个服务器。
   * 不同服务器的相同 group_key 会被聚合到同一分组（UI 不标注来源）。
   */
  static async loadAllGroupedLatest(deviceKeys: string[], perGroupLimit: number): Promise<GroupedLoadResult> {
    const db = await MessageCacheStore.getStore();
    const emptyResult: GroupedLoadResult = {
      messages: [] as NotifyMessage[],
      totals: new Map<string, number>(),
    };
    if (!db || deviceKeys.length === 0) {
      return emptyResult;
    }
    try {
      const placeholders: string = deviceKeys.map(() => '?').join(',');
      const args: string[] = deviceKeys.slice();

      // 1) 查询所有 distinct group_key（含空串代表无分组）
      const keys: string[] = [];
      const rsKeys: relationalStore.ResultSet = await db.querySql(
        `SELECT DISTINCT group_key FROM ${TABLE_MSG} WHERE device_key IN (${placeholders})`, args);
      if (rsKeys.goToFirstRow()) {
        const idx: number = rsKeys.getColumnIndex('group_key');
        do {
          keys.push(rsKeys.getString(idx));
        } while (rsKeys.goToNextRow());
      }
      rsKeys.close();
      if (keys.length === 0) {
        return emptyResult;
      }

      // 2) 对每个 group_key 查询最新 perGroupLimit 条 + 总数（跨所有 device_key）
      const totals: Map<string, number> = new Map<string, number>();
      const all: NotifyMessage[] = [];
      for (let i = 0; i < keys.length; i++) {
        const gk: string = keys[i];
        const msgArgs: Array<string | number> = deviceKeys.slice();
        msgArgs.push(gk);
        msgArgs.push(perGroupLimit);
        const rs: relationalStore.ResultSet = await db.querySql(
          `SELECT * FROM ${TABLE_MSG} WHERE device_key IN (${placeholders}) AND group_key=? ` +
          `ORDER BY timestamp DESC, id DESC LIMIT ?`,
          msgArgs);
        if (rs.goToFirstRow()) {
          do {
            all.push(rowToMessage(rs));
          } while (rs.goToNextRow());
        }
        rs.close();
        // 该 group_key 总数（跨所有 device_key）
        const cntArgs: string[] = deviceKeys.slice();
        cntArgs.push(gk);
        const rsCnt: relationalStore.ResultSet = await db.querySql(
          `SELECT COUNT(*) AS cnt FROM ${TABLE_MSG} WHERE device_key IN (${placeholders}) AND group_key=?`,
          cntArgs);
        let cnt: number = 0;
        if (rsCnt.goToFirstRow()) {
          cnt = rsCnt.getLong(rsCnt.getColumnIndex('cnt'));
        }
        rsCnt.close();
        totals.set(gk, cnt);
      }

      // 3) 合并后按 timestamp DESC（新→旧）整体排序
      all.sort((a: NotifyMessage, b: NotifyMessage) => {
        if (b.timestamp !== a.timestamp) {
          return b.timestamp - a.timestamp;
        }
        return b.id - a.id;
      });
      return { messages: all, totals };
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'loadAllGroupedLatest 失败：%{public}s', formatError(err));
      return emptyResult;
    }
  }

  /** 跨多个 device_key 查询所有 group_key 的真实总数（"全部"视图模式下徽标刷新用） */
  static async getAllGroupTotals(deviceKeys: string[]): Promise<Map<string, number>> {
    const totals: Map<string, number> = new Map<string, number>();
    const db = await MessageCacheStore.getStore();
    if (!db || deviceKeys.length === 0) {
      return totals;
    }
    try {
      const placeholders: string = deviceKeys.map(() => '?').join(',');
      const sql: string =
        `SELECT group_key, COUNT(*) AS cnt FROM ${TABLE_MSG} WHERE device_key IN (${placeholders}) GROUP BY group_key`;
      const rs: relationalStore.ResultSet = await db.querySql(sql, deviceKeys);
      if (rs.goToFirstRow()) {
        const keyIdx: number = rs.getColumnIndex('group_key');
        const cntIdx: number = rs.getColumnIndex('cnt');
        do {
          totals.set(rs.getString(keyIdx), rs.getLong(cntIdx));
        } while (rs.goToNextRow());
      }
      rs.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'getAllGroupTotals 失败：%{public}s', formatError(err));
    }
    return totals;
  }

  /**
   * 跨多个 device_key 加载某 group_key 下比 beforeId 更老的 N 条（"全部"视图模式组内加载更多）。
   * 不同服务器 id 空间独立，beforeId 取内存中该组最小 id，查询所有 device_key 中 id < beforeId 的消息。
   */
  static async loadAllGroupOlder(deviceKeys: string[], groupKey: string,
    beforeId: number, limit: number): Promise<NotifyMessage[]> {
    const db = await MessageCacheStore.getStore();
    if (!db || deviceKeys.length === 0 || beforeId <= 0) {
      return [];
    }
    const list: NotifyMessage[] = [];
    try {
      const placeholders: string = deviceKeys.map(() => '?').join(',');
      const args: Array<string | number> = deviceKeys.slice();
      args.push(groupKey);
      args.push(beforeId);
      args.push(limit);
      const sql: string =
        `SELECT * FROM ${TABLE_MSG} WHERE device_key IN (${placeholders}) AND group_key=? AND id < ? ` +
        `ORDER BY id DESC LIMIT ?`;
      const rs: relationalStore.ResultSet = await db.querySql(sql, args);
      if (rs.goToFirstRow()) {
        do {
          list.push(rowToMessage(rs));
        } while (rs.goToNextRow());
      }
      rs.close();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'loadAllGroupOlder 失败：%{public}s', formatError(err));
    }
    return list;
  }

  /** 按 (deviceKey, id) 对列表删除（跨服务器多选删除用，避免不同服务器同 id 误删） */
  static async deleteByDeviceIdPairs(pairs: DeviceIdPair[]): Promise<void> {
    if (!pairs || pairs.length === 0) {
      return;
    }
    const db = await MessageCacheStore.getStore();
    if (!db) {
      return;
    }
    try {
      // 逐条删除：不同 deviceKey 的 id 可能相同，无法用单条 IN 语句
      for (let i = 0; i < pairs.length; i++) {
        await db.executeSql(
          `DELETE FROM ${TABLE_MSG} WHERE device_key=? AND id=?`,
          [pairs[i].deviceKey, pairs[i].id]);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'deleteByDeviceIdPairs 失败：%{public}s', formatError(err));
    }
  }

  /** 清空所有设备的缓存与元信息（"全部"视图模式下清空全部消息用） */
  static async clearAllDevices(): Promise<void> {
    const db = await MessageCacheStore.getStore();
    if (!db) {
      return;
    }
    try {
      await db.executeSql(`DELETE FROM ${TABLE_MSG}`);
      await db.executeSql(`DELETE FROM ${TABLE_META}`);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'clearAllDevices 失败：%{public}s', formatError(err));
    }
  }
}
