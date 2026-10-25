import { describe, expect, it } from '@ohos/hypium';
import { NotifyMessage } from '../main/ets/model/NotifyMessage';
import { NotifyExportService } from '../main/ets/services/NotifyExportService';

/** Markdown 是独立正文，不由普通 body 的内容或布尔开关推断。 */
export default function markdownTest(): void {
  describe('MarkdownMessage', () => {
    it('preservesExtrasMarkdownAndPlainBody', 0, () => {
      const raw: Record<string, Object> = JSON.parse(
        '{"body":"纯文本摘要","extras":{"markdown":"    code\\n\\n**正文**"}}');
      const message: NotifyMessage = NotifyMessage.fromRaw(raw);
      expect(message.hasMarkdown()).assertTrue();
      expect(message.markdown).assertEqual('    code\n\n**正文**');
      expect(message.body).assertEqual('纯文本摘要');
    });

    it('ignoresMissingBlankAndNonStringMarkdown', 0, () => {
      const samples: string[] = [
        '{"body":"**普通正文**"}',
        '{"body":"普通正文","markdown":true}',
        '{"body":"普通正文","markdown":1}',
        '{"body":"普通正文","markdown":" \\n "}'
      ];
      samples.forEach((sample: string) => {
        const raw: Record<string, Object> = JSON.parse(sample);
        expect(NotifyMessage.fromRaw(raw).hasMarkdown()).assertFalse();
      });
    });

    it('supportsTopLevelAndMarkdownOnlyFallback', 0, () => {
      const raw: Record<string, Object> = JSON.parse('{"markdown":"# 标题"}');
      const message: NotifyMessage = NotifyMessage.fromRaw(raw);
      expect(message.markdown).assertEqual('# 标题');
      expect(message.body).assertEqual('# 标题');
    });

    it('decryptionReplacesAndClearsPreviousMarkdown', 0, () => {
      const message: NotifyMessage = new NotifyMessage();
      const markdown: Record<string, Object> = JSON.parse('{"markdown":"**解密正文**"}');
      message.applyDecrypted(markdown);
      expect(message.hasMarkdown()).assertTrue();
      expect(message.body).assertEqual('**解密正文**');
      const plain: Record<string, Object> = JSON.parse('{"body":"改为普通正文"}');
      message.applyDecrypted(plain);
      expect(message.hasMarkdown()).assertFalse();
      expect(message.body).assertEqual('改为普通正文');
    });

    it('exportRetainsMarkdownForRoundTrip', 0, () => {
      const raw: Record<string, Object> = JSON.parse(
        '{"id":7,"body":"摘要","extras":{"markdown":"| A | B |\\n|---|---|\\n| 1 | 2 |"}}');
      const message: NotifyMessage = NotifyMessage.fromRaw(raw);
      const exported: Object[] = JSON.parse(NotifyExportService.serializeMessages([message], 'key'));
      const restored: NotifyMessage = NotifyMessage.fromRaw(exported[0] as Record<string, Object>);
      expect(restored.markdown).assertEqual(message.markdown);
      expect(restored.body).assertEqual('摘要');
    });

    it('decryptionFailureKeepsSafePlaceholder', 0, () => {
      const message: NotifyMessage = new NotifyMessage();
      message.encrypted = true;
      message.ciphertext = 'ciphertext';
      message.title = NotifyMessage.ENCRYPTION_TITLE;
      message.body = NotifyMessage.MISSING_KEY_BODY;
      message.markdown = '**不能替代解密失败占位**';
      expect(message.hasMarkdown()).assertFalse();
    });
  });
}
