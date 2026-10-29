import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shitu/services/tts_service.dart';

/// 用方法通道 mock 扮演设备 TTS 引擎，验证 SystemTtsService 的探活与
/// 错误冒泡（真机「完全无声」修复：无引擎/缺中文包/播报被拒都不许静默）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// [engines] 引擎列表；[zhAvailable] zh-CN 是否可用；[speakResult] speak 返回值。
  void mockEngine({
    required List<String> engines,
    required bool zhAvailable,
    int speakResult = 1,
    List<String>? callLog,
  }) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      callLog?.add(call.method);
      return switch (call.method) {
        'getEngines' => engines,
        'isLanguageAvailable' => zhAvailable,
        'setLanguage' => 1,
        'setVolume' || 'setSpeechRate' || 'setPitch' => 1,
        'speak' => speakResult,
        'stop' => 1,
        _ => null,
      };
    });
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('无任何引擎：探活判不可用并给中文原因，speak 抛 TtsUnavailableException',
      () async {
    mockEngine(engines: const [], zhAvailable: false);
    final service = SystemTtsService();
    final readiness = await service.probe();
    expect(readiness.available, isFalse);
    expect(readiness.error, contains('未检测到可用的语音合成引擎'));
    await expectLater(
      service.speak('前方三百米右转'),
      throwsA(isA<TtsUnavailableException>()),
    );
  });

  test('引擎就绪且 zh-CN 可用：探活通过并设置中文语言，speak 正常', () async {
    final log = <String>[];
    mockEngine(
      engines: const ['com.google.android.tts'],
      zhAvailable: true,
      callLog: log,
    );
    final service = SystemTtsService();
    final readiness = await service.probe();
    expect(readiness.available, isTrue);
    expect(readiness.warning, isNull);
    expect(log, contains('setLanguage'));
    await service.speak('前方三百米右转，进入深南大道');
    expect(log, contains('speak'));
    expect(service.isReady, isTrue);
  });

  test('缺中文语音数据：探活降级可用并带明确警告，不假装设了中文', () async {
    final log = <String>[];
    mockEngine(
      engines: const ['com.google.android.tts'],
      zhAvailable: false,
      callLog: log,
    );
    final service = SystemTtsService();
    final readiness = await service.probe();
    expect(readiness.available, isTrue);
    expect(readiness.warning, contains('未检测到中文语音数据'));
    // 仍可尝试播报（引擎默认语言），但不能静默——warning 已在 readiness 里。
    await service.speak('前方三百米右转');
    expect(log, contains('speak'));
  });

  test('speak 返回 0（被引擎丢弃）：抛 TtsUnavailableException 冒泡', () async {
    mockEngine(
      engines: const ['com.google.android.tts'],
      zhAvailable: true,
      speakResult: 0,
    );
    final service = SystemTtsService();
    await service.probe();
    await expectLater(
      service.speak('前方三百米右转'),
      throwsA(isA<TtsUnavailableException>()),
    );
  });

  test('探活结果缓存：多次 probe 只查一次引擎', () async {
    var engineQueries = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getEngines') {
        engineQueries++;
        return ['com.google.android.tts'];
      }
      return switch (call.method) {
        'isLanguageAvailable' => true,
        _ => 1,
      };
    });
    final service = SystemTtsService();
    await service.probe();
    await service.probe();
    expect(engineQueries, 1);
  });
}
