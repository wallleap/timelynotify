// 服务器配置条目（对应 Bark 里的"服务器"列表项）
export class ServerEntry extends Object {
  id: string = '';
  name: string = '';
  baseURL: string = '';
  isBuiltIn: boolean = false;
  // per-server 保存的 device_key；切换 server 时用此 key 还原/验证
  deviceKey: string = '';
  // per-server 保存的 client token（X-Gotify-Key 认证）；留空 = 使用内置默认 token
  clientToken: string = '';
  // 最近一次同步确认的历史数据库实例 ID；为空表示旧版服务端尚未提供。
  instanceId: string = '';
  // 本地历史命名空间（含旧实例），切换数据库实例时不丢弃已迁移通知。
  historyKeys: string[] = [];

  constructor(id?: string, name?: string, baseURL?: string, isBuiltIn?: boolean, deviceKey?: string,
    clientToken?: string) {
    super();
    this.id = id || '';
    this.name = name || '';
    this.baseURL = baseURL || '';
    this.isBuiltIn = isBuiltIn || false;
    this.deviceKey = deviceKey || '';
    this.clientToken = clientToken || '';
  }
}
