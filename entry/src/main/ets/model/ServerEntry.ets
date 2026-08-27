// 服务器配置条目（对应 Bark 里的"服务器"列表项）
export class ServerEntry extends Object {
  id: string = '';
  name: string = '';
  baseURL: string = '';
  isBuiltIn: boolean = false;
  // per-server 保存的 device_key；切换 server 时用此 key 还原/验证
  deviceKey: string = '';

  constructor(id?: string, name?: string, baseURL?: string, isBuiltIn?: boolean, deviceKey?: string) {
    super();
    this.id = id || '';
    this.name = name || '';
    this.baseURL = baseURL || '';
    this.isBuiltIn = isBuiltIn || false;
    this.deviceKey = deviceKey || '';
  }
}
