/** 通知测试卡片与实际测试推送共用的参数，避免示例命令和发送内容不一致。 */
export const TEST_PUSH_TITLE: string = '[订阅通知] 及时通知推送';
export const TEST_PUSH_BODY: string = '这是一条测试通知，收到即表示订阅推送链路工作正常';
export const TEST_PUSH_ICON: string = 'https://static.wallleap.cn/temp/nwvgnm7l2on5u6c531mo.jpg';
export const TEST_PUSH_GROUP: string = 'example';
export const TEST_PUSH_TTL: number = 600;
export const TEST_PUSH_SOUND: string = 'multiwayinvitation';

/** V2 /push 的测试请求体；字段同时用于生成 POST JSON 示例。 */
export class TestPushPayload extends Object {
  device_key: string = '';
  title: string = TEST_PUSH_TITLE;
  body: string = TEST_PUSH_BODY;
  icon: string = TEST_PUSH_ICON;
  group: string = TEST_PUSH_GROUP;
  ttl: number = TEST_PUSH_TTL;
  sound: string = TEST_PUSH_SOUND;
}

/** 创建指定设备 Key 的测试请求体。 */
export function createTestPushPayload(deviceKey: string): TestPushPayload {
  const payload = new TestPushPayload();
  payload.device_key = deviceKey;
  return payload;
}

/** 去掉服务器 URL 的尾随斜杠，保证拼接推送路径时只出现一个分隔符。 */
function trimTrailingSlash(baseURL: string): string {
  let value: string = baseURL;
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

/** 把 URL 或 JSON 当作单个 shell 参数引用，避免地址中的特殊字符被 shell 执行。 */
function shellQuote(value: string): string {
  return `'${value.split("'").join("'\"'\"'")}'`;
}

/** GET 示例：原文标题/正文可读，运行时由 jq 编码路径，查询参数保持 ?key=value&key=value 形式。 */
export function buildTestGetCode(baseURL: string, deviceKey: string): string {
  const base: string = trimTrailingSlash(baseURL);
  const query: string = `icon=${encodeURIComponent(TEST_PUSH_ICON)}` +
    `&group=${encodeURIComponent(TEST_PUSH_GROUP)}` +
    `&ttl=${TEST_PUSH_TTL}` +
    `&sound=${encodeURIComponent(TEST_PUSH_SOUND)}`;
  return `title=$(printf %s ${shellQuote(TEST_PUSH_TITLE)} | jq -sRr @uri)\n` +
    `body=$(printf %s ${shellQuote(TEST_PUSH_BODY)} | jq -sRr @uri)\n` +
    `base_url=${shellQuote(`${base}/${encodeURIComponent(deviceKey)}`)}\n` +
    `curl "$base_url/$title/$body?${query}"`;
}

/** POST 示例：使用 JSON 请求体，与客户端按钮发送的字段一致。 */
export function buildTestPostCode(baseURL: string, deviceKey: string): string {
  const url: string = `${trimTrailingSlash(baseURL)}/push`;
  // JSON 各行相对 --data-raw 缩进两格，字段仍保持标准的两格层级。
  const json: string = JSON.stringify(createTestPushPayload(deviceKey), null, 2).replace(/\n/g, '\n  ');
  return `curl -X POST ${shellQuote(url)} \\\n` +
    `  -H 'Content-Type: application/json' \\\n` +
    `  --data-raw ${shellQuote(json)}`;
}
