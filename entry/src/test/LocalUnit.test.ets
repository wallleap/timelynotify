import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { EncryptionConfigService } from '../main/ets/services/EncryptionConfigService';
import { EncryptionConfig } from '../main/ets/model/EncryptionConfig';
import { MessageCryptoService } from '../main/ets/services/MessageCryptoService';
import { NotifyMessage } from '../main/ets/model/NotifyMessage';
import { NotifyExportService } from '../main/ets/services/NotifyExportService';
import { AutoCopyService, AutoCopySelection } from '../main/ets/services/AutoCopyService';
import { formatExpiryDescription, formatNotifyTime, isExpiringSoon } from '../main/ets/components/notify/NotifyViewTypes';
import { areGroupMessagesSelected, retainExpandableGroups, setGroupMessagesSelection, setSelectedMessage, toggleGroupMessages, toggleSelectedMessage } from '../main/ets/components/notify/NotifySelectionUtils';

class RawMessageExtras extends Object {
  ciphertext: string = '';
  iv: string = '';
  icon: string = '';
  image: string = '';
  isarchive: Object | undefined = undefined;
  ttl: Object | undefined = undefined;
  copy: string = '';
  autocopy: Object | undefined = undefined;
}

class RawNotifyMessage extends Object {
  id: number = 0;
  body: string = '';
  extras: RawMessageExtras = new RawMessageExtras();
}

class CryptoVector extends Object {
  algorithm: string = '';
  mode: string = '';
  key: string = '';
  iv: string = '';
  ciphertext: string = '';
}

function vector(algorithm: string, mode: string, key: string, iv: string, ciphertext: string): CryptoVector {
  const value = new CryptoVector();
  value.algorithm = algorithm;
  value.mode = mode;
  value.key = key;
  value.iv = iv;
  value.ciphertext = ciphertext;
  return value;
}

/** AutoCopyService.selectCandidate 单测用消息构造器。 */
class AutoCopyTestHelper {
  static makeMessage(deviceKey: string, id: number, timestamp: number,
    copy: string, autoCopy: boolean): NotifyMessage {
    const m: NotifyMessage = new NotifyMessage();
    m.deviceKey = deviceKey;
    m.id = id;
    m.timestamp = timestamp;
    m.copy = copy;
    m.autoCopy = autoCopy;
    return m;
  }
}

const CRYPTO_VECTORS: CryptoVector[] = [
  vector('AES128', 'CBC', '1234567890abcdef', '1234567890abcdef',
    '1cjTdELyfXqJx2T3vcw9+Oo16aTSTPhRELD+39mUCgdJK3LcsHKwg4KoiCdC/eXwDbIZrLa9JQ9eu/CGcNDB2AAed8OaT3b1+JQ1gHofj1pVDSOZyP2S71RnqDS8QR2P/JMga78kLEySIbIopfNDow=='),
  vector('AES128', 'ECB', '1234567890abcdef', '',
    '8a9XmNz43e4Nn4GVehzS4xE+KAK6H5ww/BThWr69x3bmp0aFH63z2Fm+jzRx+o+sotEuOgjMTZ64tfl9uGKW98upP44ZKPiYG31A4BP14cBZadQB4LPLCfYe1Br7ZESAi+ljX1pRpKmhG8bEUuAdVA=='),
  vector('AES128', 'GCM', '1234567890abcdef', '123456789012',
    'GYf6XJIgEN9vbgfKt02YkEgOYME0uZg8PrXaoR9XiWlv2JZmwyBc+sXssJjb3Ra2+dqPFzo9BPolHj/eJXjxhTpAU398c/JxNo16ItwedjbkJj/47WGG0DGuDGkDbX5wcT9pGCX+67D0NbVKl+I/x5AbbKzNMBBW'),
  vector('AES192', 'CBC', '1234567890abcdefghijklmn', '1234567890abcdef',
    '6Z5sLPJemKPAcuiM+Kd25BhrhBugNNwE8RpR7EZmY9/rAnke6CDkR8bti8Easir9E/7zAMspW1TgfvYcpQK9ICMCSa5iwCjapBfJUbZZ16VGIgo7V+KJCd1vqob5uNNqyDT0t+un9RrwSAtt6GoaWw=='),
  vector('AES192', 'ECB', '1234567890abcdefghijklmn', '',
    'ZJT1xax1NrzU+OhahfIEevkH/m1EVaU/ZujGOPHh160fR4Rgqz1lRwNlWJ/FXpi7W0+jpu7vfsbUQm6NVGADLSDMwWA+2YyxatZ+dmqREmIpRyv+fu2A6ZPfuxVIX4UKcQvzNuysS/Bd1aSC7djCFA=='),
  vector('AES192', 'GCM', '1234567890abcdefghijklmn', '123456789012',
    '/sDg37KhA/LUjYGw9SZnTnyAaoZW81Bj8uzgl3C7JkFbFx0vNS/7AZ0cY3XEUeqB44BKmqcjg5VlHKG5KfAMv48Mi2pkXcmWMKYk2HKuJv965WcV1dwUMKMGPDGgT2hnkmhexdp2CGd2193dSgTiI7HandYThFS4'),
  vector('AES256', 'CBC', '1234567890abcdefghijklmnopqrstuv', '1234567890abcdef',
    'xP3OO+FzTIhsawNFJaQPHobgfjZH8tcxesY6L0tZUoAtwxcSsHkwWOpPhlJUJWm8I2W5ySe1ePDRBTVONbES9HTroZgIkREeI1uKaubBpxJwsmH4Md1pTewBx8FUketIDX34LyRubVRnrM5OJ7DplA=='),
  vector('AES256', 'ECB', '1234567890abcdefghijklmnopqrstuv', '',
    'hYaYGOdgy9E/VdfE11T1shz4XUNTOy3ltmFq9uG8U8EWpZwtiiBAizBa/gDdfnH8TWWJ5DajZSGZ08J86R3atZebBAGiOkyr7vRarv/NEX1AKMIPX8X7wzexkSNHdO/ebVMpgbt6tdd6e3c+08X5gA=='),
  vector('AES256', 'GCM', '1234567890abcdefghijklmnopqrstuv', '123456789012',
    'XNc7nm5EyCS3WU8RVz3bcmJF+DLU5cLu4hGZe0YlykWOYY+NY5/DU6czsdEp3togBhprXh5ab+8BCuKjHqd+/WUTwIyzyBtSz75pWbhsMkVRhY1v0yhJiBdpKvEDEeoiPyEgfHDNPaxlkQfhvBxNnjB6Mi/jQ2pA'),
];

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    it('assertContain', 0, () => {
      // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
      let a = 'abc';
      let b = 'b';
      // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });
    it('keepsGroupSelectionAndActionCountInSync', 0, () => {
      const first: NotifyMessage = new NotifyMessage();
      first.id = 1;
      const second: NotifyMessage = new NotifyMessage();
      second.id = 2;
      const group: NotifyMessage[] = [first, second];
      let selected: number[] = toggleSelectedMessage([], first.id);
      expect(selected.length).assertEqual(1);
      expect(areGroupMessagesSelected(selected, group)).assertFalse();
      selected = toggleGroupMessages(selected, group);
      expect(selected.length).assertEqual(2);
      expect(areGroupMessagesSelected(selected, group)).assertTrue();
      selected = toggleSelectedMessage(selected, second.id);
      expect(selected.length).assertEqual(1);
      expect(areGroupMessagesSelected(selected, group)).assertFalse();
      selected = toggleGroupMessages(selected, group);
      expect(selected.length).assertEqual(2);
      selected = toggleGroupMessages(selected, group);
      expect(selected.length).assertEqual(0);
    });
    it('ignoresRepeatedCheckboxStateUpdates', 0, () => {
      const first: NotifyMessage = new NotifyMessage();
      first.id = 1;
      const second: NotifyMessage = new NotifyMessage();
      second.id = 2;
      const group: NotifyMessage[] = [first, second];
      const selected: number[] = setSelectedMessage([], first.id, true);
      expect(setSelectedMessage(selected, first.id, true) === selected).assertTrue();
      const groupSelected: number[] = setGroupMessagesSelection(selected, group, true);
      expect(groupSelected.length).assertEqual(2);
      expect(setGroupMessagesSelection(groupSelected, group, true) === groupSelected).assertTrue();
      const cleared: number[] = setGroupMessagesSelection(groupSelected, group, false);
      expect(cleared.length).assertEqual(0);
      expect(setGroupMessagesSelection(cleared, group, false) === cleared).assertTrue();
    });
    it('collapsesGroupWhenOnlyOneMessageRemains', 0, () => {
      // g1 删除后仅剩 1 条且真实总数为 1；g2 仍有 2 条；空 group_key 代表“默认”分组。
      const g1Only: NotifyMessage = new NotifyMessage();
      g1Only.id = 1;
      g1Only.group = 'g1';
      const g2First: NotifyMessage = new NotifyMessage();
      g2First.id = 2;
      g2First.group = 'g2';
      const g2Second: NotifyMessage = new NotifyMessage();
      g2Second.id = 3;
      g2Second.group = 'g2';
      const defaultOnly: NotifyMessage = new NotifyMessage();
      defaultOnly.id = 4;
      defaultOnly.group = '';
      const messages: NotifyMessage[] = [g1Only, g2First, g2Second, defaultOnly];
      const totals: Map<string, number> = new Map<string, number>();
      totals.set('g1', 1);
      totals.set('g2', 2);
      totals.set('', 1);
      const retained: string[] = retainExpandableGroups(messages, ['g1', 'g2', ''], totals);
      expect(retained.length).assertEqual(1);
      expect(retained[0]).assertEqual('g2');
      // 大分组只加载部分消息：真实总数仍大于 1 时保留展开，避免收起后看不到“加载更多”入口。
      const partialTotals: Map<string, number> = new Map<string, number>();
      partialTotals.set('g1', 5);
      expect(retainExpandableGroups([g1Only], ['g1'], partialTotals).length).assertEqual(1);
      // totals 缺省时回退内存计数：只剩 1 条同样自动收起。
      expect(retainExpandableGroups([g1Only], ['g1']).length).assertEqual(0);
      // 整组删光时移除展开状态。
      expect(retainExpandableGroups([], ['g1'], totals).length).assertEqual(0);
    });
    it('exportsEveryLocalNotificationWithDecryptedFields', 0, () => {
      const first: NotifyMessage = new NotifyMessage();
      first.id = 1;
      first.title = '第一条';
      first.body = '解密后的正文';
      first.icon = 'https://example.com/icon.png';
      first.image = 'https://example.com/image.png';
      first.encrypted = true;
      first.ciphertext = 'encrypted-data';
      first.deviceKey = 'device-a';
      const second: NotifyMessage = new NotifyMessage();
      second.id = 2;
      second.title = '第二条';
      second.deviceKey = 'device-a';
      const text: string = NotifyExportService.serializeMessages([first, second], 'device-a');
      const records: Object[] = JSON.parse(text) as Object[];
      expect(records.length).assertEqual(2);
      expect(text).assertContain('解密后的正文');
      expect(text).assertContain('https://example.com/icon.png');
      expect(text).assertContain('https://example.com/image.png');
      expect(text).assertContain('encrypted-data');
    });
    it('matchesAesKeyLengths', 0, () => {
      expect(EncryptionConfigService.expectedKeyBytes('AES128')).assertEqual(16);
      expect(EncryptionConfigService.expectedKeyBytes('AES192')).assertEqual(24);
      expect(EncryptionConfigService.expectedKeyBytes('AES256')).assertEqual(32);
    });
    it('generatesPrintableKeysForAllAesAlgorithms', 0, () => {
      const algorithms: string[] = ['AES128', 'AES192', 'AES256'];
      for (let i: number = 0; i < algorithms.length; i++) {
        const generated: string = EncryptionConfigService.generateKey(algorithms[i]);
        expect(EncryptionConfigService.utf8Length(generated))
          .assertEqual(EncryptionConfigService.expectedKeyBytes(algorithms[i]));
        expect(/^[A-Za-z0-9_-]+$/.test(generated)).assertTrue();
      }
    });
    it('validatesModePaddingAndUtf8KeyBytes', 0, () => {
      const config = new EncryptionConfig();
      config.enabled = true;
      config.algorithm = 'AES128';
      config.mode = 'GCM';
      config.padding = 'PKCS7';
      config.key = '1234567890abcdef';
      expect(EncryptionConfigService.validate(config)).assertEqual('GCM 必须使用 NoPadding');
      config.padding = 'NoPadding';
      config.key = '密钥1234567890';
      expect(EncryptionConfigService.utf8Length(config.key)).assertEqual(16);
      expect(EncryptionConfigService.validate(config)).assertEqual('');
    });
    it('marksCiphertextMessagesAsEncrypted', 0, () => {
      const encryptedRaw: RawNotifyMessage = new RawNotifyMessage();
      encryptedRaw.id = 1;
      encryptedRaw.extras.ciphertext = 'base64-data';
      encryptedRaw.extras.iv = '1234567890123456';
      const plainRaw: RawNotifyMessage = new RawNotifyMessage();
      plainRaw.id = 2;
      plainRaw.body = 'plain';
      const encrypted: NotifyMessage = NotifyMessage.fromRaw(encryptedRaw as Object as Record<string, Object>);
      const plain: NotifyMessage = NotifyMessage.fromRaw(plainRaw as Object as Record<string, Object>);
      expect(encrypted.encrypted).assertTrue();
      expect(encrypted.migrationReady).assertFalse();
      expect(plain.encrypted).assertFalse();
      expect(plain.migrationReady).assertTrue();
    });
    it('parsesArchiveAndTtlWithBackwardCompatibleDefaults', 0, () => {
      const defaultRaw: RawNotifyMessage = new RawNotifyMessage();
      const defaultMessage: NotifyMessage = NotifyMessage.fromRaw(
        defaultRaw as Object as Record<string, Object>);
      expect(defaultMessage.archive).assertTrue();
      expect(defaultMessage.expiresAt).assertEqual(0);

      const retainedRaw: RawNotifyMessage = new RawNotifyMessage();
      retainedRaw.extras.isarchive = '1';
      retainedRaw.extras.ttl = '60';
      const retainedRecord = retainedRaw as Object as Record<string, Object>;
      retainedRecord['date'] = '2026-09-23T00:00:00Z';
      const retained: NotifyMessage = NotifyMessage.fromRaw(retainedRecord);
      expect(retained.archive).assertTrue();
      expect(retained.expiresAt).assertEqual(Date.parse('2026-09-23T00:01:00Z'));

      const transientRaw: RawNotifyMessage = new RawNotifyMessage();
      transientRaw.extras.isarchive = '0';
      const transient: NotifyMessage = NotifyMessage.fromRaw(
        transientRaw as Object as Record<string, Object>);
      expect(transient.archive).assertFalse();
    });
    it('appliesEncryptedArchiveAndTtlPolicyAfterDecryption', 0, () => {
      const message = new NotifyMessage();
      message.timestamp = Date.parse('2026-09-23T00:00:00Z');
      message.applyDecrypted({ 'isArchive': 0, 'ttl': 30 });
      expect(message.archive).assertFalse();
      expect(message.expiresAt).assertEqual(Date.parse('2026-09-23T00:00:30Z'));
      expect(message.isExpired(Date.parse('2026-09-23T00:00:29Z'))).assertFalse();
      expect(message.isExpired(Date.parse('2026-09-23T00:00:30Z'))).assertTrue();
    });
    it('requestsLocalNotificationOnlyForDecryptedTransientCiphertext', 0, () => {
      const message = new NotifyMessage();
      message.encrypted = true;
      message.archive = false;
      message.migrationReady = true;
      expect(message.needsDecryptedNotification(100)).assertTrue();
      message.migrationReady = false;
      expect(message.needsDecryptedNotification(100)).assertFalse();
      message.migrationReady = true;
      message.archive = true;
      expect(message.needsDecryptedNotification(100)).assertFalse();
      message.archive = false;
      message.expiresAt = 100;
      expect(message.needsDecryptedNotification(100)).assertFalse();
    });
    it('formatsTtlExpiryForListAndDetail', 0, () => {
      const now: number = Date.parse('2026-09-23T00:00:00Z');
      expect(isExpiringSoon(0, now)).assertFalse();
      expect(isExpiringSoon(now + 30 * 60 * 1000, now)).assertTrue();
      expect(isExpiringSoon(now + 60 * 60 * 1000, now)).assertFalse();
      expect(formatExpiryDescription(0, now)).assertEqual('');
      expect(formatExpiryDescription(now + 30 * 60 * 1000, now)).assertEqual('约 30 分钟后过期');
      expect(formatExpiryDescription(now + 3 * 60 * 60 * 1000, now)).assertEqual('约 3 小时后过期');
      expect(formatExpiryDescription(Date.parse('2026-09-25T12:30:00Z'), now))
        .assertEqual(`${formatNotifyTime(Date.parse('2026-09-25T12:30:00Z'))} 过期`);
      expect(formatExpiryDescription(now, now)).assertEqual('已过期');
    });
    it('appliesAllDecryptedDisplayFields', 0, () => {
      const message = new NotifyMessage();
      message.ciphertext = 'original-ciphertext';
      message.iv = 'original-iv';
      message.encrypted = true;
      message.applyDecrypted({
        'title': 'T',
        'body': 'B',
        'subtitle': 'S',
        'icon': 'https://example.com/icon.png',
        'image': 'https://example.com/image.png',
        'group': ' G ',
        'url': ' https://example.com ',
        'inboxContent': ['1', '2'],
      });
      expect(message.title).assertEqual('T');
      expect(message.body).assertEqual('B');
      expect(message.subtitle).assertEqual('S');
      expect(message.icon).assertEqual('https://example.com/icon.png');
      expect(message.image).assertEqual('https://example.com/image.png');
      expect(message.group).assertEqual('G');
      expect(message.url).assertEqual('https://example.com');
      expect(message.inboxContent.length).assertEqual(2);
      expect(message.ciphertext).assertEqual('original-ciphertext');
      expect(message.iv).assertEqual('original-iv');
      expect(message.encrypted).assertTrue();
      expect(message.migrationReady).assertTrue();
    });
    it('keepsRemoteIconAndImageSeparate', 0, () => {
      const raw: RawNotifyMessage = new RawNotifyMessage();
      raw.extras.icon = 'https://example.com/icon.png';
      raw.extras.image = 'https://example.com/image.png';
      const message: NotifyMessage = NotifyMessage.fromRaw(raw as Object as Record<string, Object>);
      expect(message.icon).assertEqual('https://example.com/icon.png');
      expect(message.image).assertEqual('https://example.com/image.png');
    });
    it('decryptsAllSupportedAesVariants', 0, async () => {
      for (let i: number = 0; i < CRYPTO_VECTORS.length; i++) {
        const item: CryptoVector = CRYPTO_VECTORS[i];
        const config = new EncryptionConfig();
        config.enabled = true;
        config.algorithm = item.algorithm;
        config.mode = item.mode;
        config.padding = item.mode === 'GCM' ? 'NoPadding' : 'PKCS7';
        config.key = item.key;
        const clear: Record<string, Object> = await MessageCryptoService.decrypt(
          config, item.ciphertext, item.iv);
        expect(clear['title'] as string).assertEqual('T');
        expect(clear['body'] as string).assertEqual('B');
        expect((clear['inboxContent'] as Object[]).length).assertEqual(2);
      }
    });
    it('rejectsInvalidIvAndTamperedGcmTag', 0, async () => {
      const config = new EncryptionConfig();
      config.enabled = true;
      config.algorithm = 'AES128';
      config.mode = 'CBC';
      config.padding = 'PKCS7';
      config.key = '1234567890abcdef';
      let invalidIvRejected: boolean = false;
      try {
        await MessageCryptoService.decrypt(config, CRYPTO_VECTORS[0].ciphertext, 'short');
      } catch (_err) {
        invalidIvRejected = true;
      }
      expect(invalidIvRejected).assertTrue();

      config.mode = 'GCM';
      config.padding = 'NoPadding';
      const original: string = CRYPTO_VECTORS[2].ciphertext;
      const tampered: string = `${original.substring(0, original.length - 1)}A`;
      let tamperedTagRejected: boolean = false;
      try {
        await MessageCryptoService.decrypt(config, tampered, CRYPTO_VECTORS[2].iv);
      } catch (_err) {
        tamperedTagRejected = true;
      }
      expect(tamperedTagRejected).assertTrue();
    });
    it('parsesCopyAndAutoCopyFromExtras', 0, () => {
      const raw: RawNotifyMessage = new RawNotifyMessage();
      raw.id = 1;
      raw.extras.copy = '  123456  ';
      raw.extras.autocopy = '1';
      const message: NotifyMessage = NotifyMessage.fromRaw(raw as Object as Record<string, Object>);
      expect(message.copy).assertEqual('123456');
      expect(message.autoCopy).assertTrue();

      // autocopy 真值兼容多种字符串形式
      const truthyStrings: string[] = ['1', 'true', 'TRUE', 'yes', 'on'];
      for (let i = 0; i < truthyStrings.length; i++) {
        const v: RawNotifyMessage = new RawNotifyMessage();
        v.extras.autocopy = truthyStrings[i];
        const m: NotifyMessage = NotifyMessage.fromRaw(v as Object as Record<string, Object>);
        expect(m.autoCopy).assertTrue();
      }
      // 假值
      const falsyStrings: string[] = ['0', 'no', 'off', '', 'maybe'];
      for (let i = 0; i < falsyStrings.length; i++) {
        const v: RawNotifyMessage = new RawNotifyMessage();
        v.extras.autocopy = falsyStrings[i];
        const m: NotifyMessage = NotifyMessage.fromRaw(v as Object as Record<string, Object>);
        expect(m.autoCopy).assertFalse();
      }
      // 不设 autocopy 字段（undefined）时默认 false
      const unset: NotifyMessage = NotifyMessage.fromRaw(new RawNotifyMessage() as Object as Record<string, Object>);
      expect(unset.autoCopy).assertFalse();
    });
    it('parsesCopyAutoCopyCamelCaseFromExtras', 0, () => {
      // 兼容 Bark 风格不区分大小写：extras.autoCopy（驼峰）/extras.autocopy（小写）都能解析到。
      const raw: RawNotifyMessage = new RawNotifyMessage();
      raw.id = 1;
      const record: Record<string, Object> = raw.extras as Object as Record<string, Object>;
      record['autoCopy'] = 1;
      record['copy'] = '  123456  ';
      const message: NotifyMessage = NotifyMessage.fromRaw(raw as Object as Record<string, Object>);
      expect(message.copy).assertEqual('123456');
      expect(message.autoCopy).assertTrue();

      // extras.autoCopy=true 布尔值
      const rawBool: RawNotifyMessage = new RawNotifyMessage();
      const recBool: Record<string, Object> = rawBool.extras as Object as Record<string, Object>;
      recBool['autoCopy'] = true;
      const mBool: NotifyMessage = NotifyMessage.fromRaw(rawBool as Object as Record<string, Object>);
      expect(mBool.autoCopy).assertTrue();

      // extras.Copy 驼峰（首字母大写）也能解析到 copy
      const rawCopyPascal: RawNotifyMessage = new RawNotifyMessage();
      const recPascal: Record<string, Object> = rawCopyPascal.extras as Object as Record<string, Object>;
      recPascal['Copy'] = 'abc';
      const mPascal: NotifyMessage = NotifyMessage.fromRaw(rawCopyPascal as Object as Record<string, Object>);
      expect(mPascal.copy).assertEqual('abc');
    });
    it('parsesCopyAutoCopyFromTopLevelPassthrough', 0, () => {
      const raw: RawNotifyMessage = new RawNotifyMessage();
      raw.id = 2;
      const record: Record<string, Object> = raw as Object as Record<string, Object>;
      record['copy'] = 'topcode';
      record['autocopy'] = 'true';
      const message: NotifyMessage = NotifyMessage.fromRaw(record);
      expect(message.copy).assertEqual('topcode');
      expect(message.autoCopy).assertTrue();
    });
    it('parsesCopyAutoCopyCamelCaseFromTopLevel', 0, () => {
      // 顶层驼峰 copy/autoCopy 也能解析到（兼容部分推送通道的透传格式）。
      const raw: RawNotifyMessage = new RawNotifyMessage();
      raw.id = 3;
      const record: Record<string, Object> = raw as Object as Record<string, Object>;
      record['autoCopy'] = 1;
      record['copy'] = 'topcamel';
      const message: NotifyMessage = NotifyMessage.fromRaw(record);
      expect(message.copy).assertEqual('topcamel');
      expect(message.autoCopy).assertTrue();
    });
    it('appliesDecryptedCopyAndAutoCopy', 0, () => {
      const message = new NotifyMessage();
      message.ciphertext = 'c';
      message.iv = 'i';
      message.encrypted = true;
      message.applyDecrypted({
        'title': 'T',
        'body': 'B',
        'copy': '  decCode  ',
        'autoCopy': true,
      });
      expect(message.copy).assertEqual('decCode');
      expect(message.autoCopy).assertTrue();
      expect(message.body).assertEqual('B');

      // 兼容小写 autocopy 键
      const second = new NotifyMessage();
      second.applyDecrypted({ 'copy': 'c2', 'autocopy': '1' });
      expect(second.copy).assertEqual('c2');
      expect(second.autoCopy).assertTrue();

      // 解密载荷不含 copy/autoCopy 时回退为空与 false
      const third = new NotifyMessage();
      third.applyDecrypted({ 'title': 'T', 'body': 'B' });
      expect(third.copy).assertEqual('');
      expect(third.autoCopy).assertFalse();
    });
    it('isTruthyFlagHandlesBooleanNumberAndString', 0, () => {
      // 布尔/数字通过 applyDecrypted/fromRaw 路径覆盖；这里聚焦字符串与 undefined。
      expect(NotifyMessage.isTruthyFlag(undefined)).assertFalse();
      expect(NotifyMessage.isTruthyFlag('1')).assertTrue();
      expect(NotifyMessage.isTruthyFlag('true')).assertTrue();
      expect(NotifyMessage.isTruthyFlag('YES')).assertTrue();
      expect(NotifyMessage.isTruthyFlag('on')).assertTrue();
      expect(NotifyMessage.isTruthyFlag('0')).assertFalse();
      expect(NotifyMessage.isTruthyFlag('')).assertFalse();
      expect(NotifyMessage.isTruthyFlag('maybe')).assertFalse();
    });
    it('autoCopySelectsLatestWithinWindow', 0, () => {
      const now: number = Date.parse('2026-09-23T12:00:00Z');
      // 三条 autoCopy 消息：3 分钟前、1 分钟前、6 分钟前（超窗口）
      const m1: NotifyMessage = AutoCopyTestHelper.makeMessage('dev-a', 101,
        now - 3 * 60 * 1000, 'code-old', true);
      const m2: NotifyMessage = AutoCopyTestHelper.makeMessage('dev-a', 102,
        now - 1 * 60 * 1000, 'code-new', true);
      const m3: NotifyMessage = AutoCopyTestHelper.makeMessage('dev-a', 103,
        now - 6 * 60 * 1000, 'code-stale', true);
      const processed: Set<string> = new Set<string>();
      const selection: AutoCopySelection = AutoCopyService.selectCandidate([m1, m2, m3], processed, now);
      // 选中的是时间最新的 m2
      expect(selection.target).assertEqual(m2);
      expect(selection.text).assertEqual('code-new');
      // 超窗口的 m3 计入 identitiesToMark；候选 m1、m2 也计入
      expect(selection.identitiesToMark.length).assertEqual(3);
      expect(selection.identitiesToMark.indexOf('dev-a:103') >= 0).assertTrue();
      expect(selection.identitiesToMark.indexOf('dev-a:101') >= 0).assertTrue();
      expect(selection.identitiesToMark.indexOf('dev-a:102') >= 0).assertTrue();
    });
    it('autoCopySkipsProcessedAndEmptyText', 0, () => {
      const now: number = Date.parse('2026-09-23T12:00:00Z');
      const processed: Set<string> = new Set<string>();
      // 已处理的不再选中
      const m1: NotifyMessage = AutoCopyTestHelper.makeMessage('dev-b', 1,
        now - 60 * 1000, 'code1', true);
      processed.add('dev-b:1');
      const sel1: AutoCopySelection = AutoCopyService.selectCandidate([m1], processed, now);
      expect(sel1.target === null).assertTrue();
      expect(sel1.text).assertEqual('');

      // copy 与 body 都空时，仍标记候选但 target.text 为空，调用方据此跳过复制
      const m2: NotifyMessage = AutoCopyTestHelper.makeMessage('dev-b', 2,
        now - 60 * 1000, '', true);
      m2.body = '';
      const sel2: AutoCopySelection = AutoCopyService.selectCandidate([m2], new Set<string>(), now);
      expect(sel2.target).assertEqual(m2);
      expect(sel2.text).assertEqual('');
      expect(sel2.identitiesToMark.indexOf('dev-b:2') >= 0).assertTrue();

      // autoCopy=false 的消息不参与
      const m3: NotifyMessage = AutoCopyTestHelper.makeMessage('dev-b', 3,
        now - 60 * 1000, 'code3', false);
      const sel3: AutoCopySelection = AutoCopyService.selectCandidate([m3], new Set<string>(), now);
      expect(sel3.target === null).assertTrue();
      expect(sel3.identitiesToMark.length).assertEqual(0);
    });
    it('autoCopyFallsBackToBodyWhenCopyAbsent', 0, () => {
      const now: number = Date.parse('2026-09-23T12:00:00Z');
      // copy 为空，autoCopy=true：复制回退到 body
      const m: NotifyMessage = AutoCopyTestHelper.makeMessage('dev-c', 5,
        now - 30 * 1000, '', true);
      m.body = 'body-content';
      const sel: AutoCopySelection = AutoCopyService.selectCandidate([m], new Set<string>(), now);
      expect(sel.target).assertEqual(m);
      expect(sel.text).assertEqual('body-content');
    });
    it('autoCopyBreaksTimestampTieByIdDesc', 0, () => {
      const now: number = Date.parse('2026-09-23T12:00:00Z');
      // 相同时间戳，id 大的优先；保证结果稳定不随机
      const m1: NotifyMessage = AutoCopyTestHelper.makeMessage('dev-d', 10,
        now - 60 * 1000, 'a', true);
      const m2: NotifyMessage = AutoCopyTestHelper.makeMessage('dev-d', 20,
        now - 60 * 1000, 'b', true);
      const sel: AutoCopySelection = AutoCopyService.selectCandidate([m1, m2], new Set<string>(), now);
      expect(sel.target).assertEqual(m2);
      expect(sel.text).assertEqual('b');
    });
    it('autoCopyDistinguishesSameIdAcrossDevices', 0, () => {
      const now: number = Date.parse('2026-09-23T12:00:00Z');
      // 两个服务器同 id=1；只标记其中一个已处理，另一个仍可选中
      const processed: Set<string> = new Set<string>();
      processed.add('dev-e:1');
      const m1: NotifyMessage = AutoCopyTestHelper.makeMessage('dev-e', 1,
        now - 60 * 1000, 'e-code', true);
      const m2: NotifyMessage = AutoCopyTestHelper.makeMessage('dev-f', 1,
        now - 60 * 1000, 'f-code', true);
      const sel: AutoCopySelection = AutoCopyService.selectCandidate([m1, m2], processed, now);
      // dev-e:1 已处理被跳过；选中的是 dev-f:1
      expect(sel.target).assertEqual(m2);
      expect(sel.text).assertEqual('f-code');
    });
  });
}
