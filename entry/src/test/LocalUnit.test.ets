import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { EncryptionConfigService } from '../main/ets/services/EncryptionConfigService';
import { EncryptionConfig } from '../main/ets/model/EncryptionConfig';
import { MessageCryptoService } from '../main/ets/services/MessageCryptoService';
import { NotifyMessage } from '../main/ets/model/NotifyMessage';
import { formatExpiryDescription, formatNotifyTime, isExpiringSoon } from '../main/ets/components/notify/NotifyViewTypes';

class RawMessageExtras extends Object {
  ciphertext: string = '';
  iv: string = '';
  icon: string = '';
  image: string = '';
  isarchive: Object | undefined = undefined;
  ttl: Object | undefined = undefined;
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
  });
}
