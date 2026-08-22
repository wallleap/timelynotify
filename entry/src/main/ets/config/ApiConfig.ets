// API 环境配置
export class ApiConfig {
  // 生产环境
  static readonly PROD_BASE_URL: string = 'https://timelynotify.oicode.cn';
  // 本地测试环境：⚠️ 把 192.168.31.5 替换成你 Mac 实际的局域网 IP（不能用 localhost/127.0.0.1）
  // 设备（包括 DevEco 模拟器）里的 localhost 指设备自己，不是你的 Mac
  static readonly DEV_BASE_URL: string = 'http://192.168.0.202:18080';
  // 当前环境：true = 生产，false = 本地调试
  // 本地联调时设为 false 用 DEV_BASE_URL
  static readonly USE_PRODUCTION: boolean = false;
  // 注册接口路径
  static readonly REGISTER_PATH: string = '/register';
  // 平台标识
  static readonly PLATFORM_HARMONY: string = 'harmony';

  static get baseURL(): string {
    return ApiConfig.USE_PRODUCTION ? ApiConfig.PROD_BASE_URL : ApiConfig.DEV_BASE_URL;
  }
}
