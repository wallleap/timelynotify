import { describe, it, expect } from '@ohos/hypium';
import {
  buildTestGetCode,
  buildTestPostCode,
  createTestPushPayload,
  TEST_PUSH_BODY,
  TEST_PUSH_GROUP,
  TEST_PUSH_ICON,
  TEST_PUSH_SOUND,
  TEST_PUSH_TITLE,
  TEST_PUSH_TTL
} from '../main/ets/utils/TestPushExample';

/** 通知测试卡片的 GET/POST 示例与实际发送字段必须保持一致。 */
export default function testPushExampleTest(): void {
  describe('TestPushExample', () => {
    it('buildsSamePostFieldsAsTestPush', 0, () => {
      const payload = createTestPushPayload('device-key');
      const code: string = buildTestPostCode('https://example.com/', 'device-key');
      expect(payload.device_key).assertEqual('device-key');
      expect(payload.title).assertEqual(TEST_PUSH_TITLE);
      expect(payload.body).assertEqual(TEST_PUSH_BODY);
      expect(payload.icon).assertEqual(TEST_PUSH_ICON);
      expect(payload.group).assertEqual(TEST_PUSH_GROUP);
      expect(payload.ttl).assertEqual(TEST_PUSH_TTL);
      expect(payload.sound).assertEqual(TEST_PUSH_SOUND);
      expect(code.includes("curl -X POST 'https://example.com/push'")).assertTrue();
      const indentedJson: string = JSON.stringify(payload, null, 2).replace(/\n/g, '\n  ');
      expect(code.includes(`--data-raw '${indentedJson}'`)).assertTrue();
      expect(code.includes("<<'JSON'")).assertFalse();
      expect(code.includes('\nJSON')).assertFalse();
    });

    it('buildsGetForSelectedServerAndKey', 0, () => {
      const code: string = buildTestGetCode('https://example.com/', 'device-key');
      expect(code.startsWith(`title=$(printf %s '${TEST_PUSH_TITLE}' | jq -sRr @uri)`)).assertTrue();
      expect(code.includes(`body=$(printf %s '${TEST_PUSH_BODY}' | jq -sRr @uri)`)).assertTrue();
      expect(code.includes("base_url='https://example.com/device-key'")).assertTrue();
      expect(code.includes(`?icon=${encodeURIComponent(TEST_PUSH_ICON)}`)).assertTrue();
      expect(code.includes(`&group=${TEST_PUSH_GROUP}`)).assertTrue();
      expect(code.includes(`&ttl=${TEST_PUSH_TTL}`)).assertTrue();
      expect(code.includes(`&sound=${TEST_PUSH_SOUND}`)).assertTrue();
      expect(code.includes('curl "$base_url/$title/$body?')).assertTrue();
      expect(code.includes('\n')).assertTrue();
    });

    it('changesCodeWithSelectedServer', 0, () => {
      const first: string = buildTestPostCode('https://first.example/', 'first-key');
      const second: string = buildTestPostCode('https://second.example/', 'second-key');
      const firstGet: string = buildTestGetCode('https://first.example/', 'first-key');
      const secondGet: string = buildTestGetCode('https://second.example/', 'second-key');
      expect(first.includes('https://first.example/push')).assertTrue();
      expect(first.includes('first-key')).assertTrue();
      expect(second.includes('https://second.example/push')).assertTrue();
      expect(second.includes('second-key')).assertTrue();
      expect(first === second).assertFalse();
      expect(firstGet.includes("base_url='https://first.example/first-key'")).assertTrue();
      expect(secondGet.includes("base_url='https://second.example/second-key'")).assertTrue();
      expect(firstGet === secondGet).assertFalse();
    });

    it('quotesShellSpecialCharactersInServerAddress', 0, () => {
      const code: string = buildTestPostCode("https://example.com/o'clock", 'device-key');
      expect(code.includes("o'\"'\"'clock")).assertTrue();
    });
  });
}
