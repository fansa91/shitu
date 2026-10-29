import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shitu/services/app_signature_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('formatSha1Hex', () {
    // 已知向量：发布证书指纹（公开值，设置页/申请指南里本就展示）。
    test('小写无分隔 hex → 大写冒号分隔', () {
      expect(
        AppSignatureService.formatSha1Hex(
            '601540f1350a6137f53e6e1cc6a31f9255daf85d'),
        '60:15:40:F1:35:0A:61:37:F5:3E:6E:1C:C6:A3:1F:92:55:DA:F8:5D',
      );
    });

    test('已带冒号/大写输入 → 归一化为同一格式', () {
      expect(
        AppSignatureService.formatSha1Hex(
            '60:15:40:F1:35:0A:61:37:F5:3E:6E:1C:C6:A3:1F:92:55:DA:F8:5D'),
        '60:15:40:F1:35:0A:61:37:F5:3E:6E:1C:C6:A3:1F:92:55:DA:F8:5D',
      );
    });

    test('非法输入返回 null（不硬凑）', () {
      expect(AppSignatureService.formatSha1Hex(null), isNull);
      expect(AppSignatureService.formatSha1Hex(''), isNull);
      expect(AppSignatureService.formatSha1Hex('abcd'), isNull);
      expect(AppSignatureService.formatSha1Hex('zz' * 20), isNull);
    });
  });

  group('fetchSha1（通道 mock）', () {
    const channel = MethodChannel('com.shitu.app/signature');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('原生返回 hex → 格式化后的 SHA1', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getSigningSha1Hex');
        return '601540f1350a6137f53e6e1cc6a31f9255daf85d';
      });
      final result = await AppSignatureService().fetchSha1();
      expect(result.sha1,
          '60:15:40:F1:35:0A:61:37:F5:3E:6E:1C:C6:A3:1F:92:55:DA:F8:5D');
      expect(result.error, isNull);
    });

    test('原生抛错 → 不崩，sha1 为空且带原因', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'SIGNING_ERROR', message: '未找到签名证书');
      });
      final result = await AppSignatureService().fetchSha1();
      expect(result.sha1, isNull);
      expect(result.error, contains('未找到签名证书'));
    });

    test('原生返回空 → 明确报无效，不假装有值', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      final result = await AppSignatureService().fetchSha1();
      expect(result.sha1, isNull);
      expect(result.error, isNotNull);
    });
  });
}
