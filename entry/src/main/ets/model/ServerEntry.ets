// 服务器配置条目（对应 Bark 里的"服务器"列表项）
export class ServerEntry extends Object {
  id: string = '';
  name: string = '';
  baseURL: string = '';
  isBuiltIn: boolean = false;

  constructor(id?: string, name?: string, baseURL?: string, isBuiltIn?: boolean) {
    super();
    this.id = id || '';
    this.name = name || '';
    this.baseURL = baseURL || '';
    this.isBuiltIn = isBuiltIn || false;
  }
}
