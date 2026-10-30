import 'package:flutter_test/flutter_test.dart';
import 'package:shitu/services/native_map_probe.dart';

void main() {
  group('parseProbeStatus', () {
    test('无记录 → neverTried', () {
      final s = parseProbeStatus(null, null);
      expect(s.outcome, ProbeOutcome.neverTried);
      expect(s.at, isNull);
    });

    test('loaded + 时间戳 → loaded 且带时间', () {
      const millis = 1793400000000;
      final s = parseProbeStatus('loaded', millis);
      expect(s.outcome, ProbeOutcome.loaded);
      expect(s.at, DateTime.fromMillisecondsSinceEpoch(millis));
    });

    test('started → startedOnly（启动后未完成）', () {
      final s = parseProbeStatus('started', 1793400000000);
      expect(s.outcome, ProbeOutcome.startedOnly);
      expect(s.at, isNotNull);
    });

    test('未知状态值 → neverTried（留痕损坏不误判）', () {
      expect(parseProbeStatus('weird', 1).outcome, ProbeOutcome.neverTried);
      expect(parseProbeStatus('', null).outcome, ProbeOutcome.neverTried);
    });

    test('有状态无时间戳：outcome 照常、时间为 null', () {
      final s = parseProbeStatus('loaded', null);
      expect(s.outcome, ProbeOutcome.loaded);
      expect(s.at, isNull);
    });
  });

  group('probeStatusText', () {
    test('neverTried 文案', () {
      expect(
        probeStatusText(const ProbeStatus(ProbeOutcome.neverTried, null)),
        contains('尚未试过'),
      );
    });

    test('loaded 文案带成功字样', () {
      final text = probeStatusText(
        ProbeStatus(ProbeOutcome.loaded, DateTime(2026, 10, 30, 14, 5)),
      );
      expect(text, contains('上次加载成功'));
      expect(text, contains('10月30日'));
      expect(text, contains('14:05'));
    });

    test('startedOnly 文案是疑似崩溃口径', () {
      final text = probeStatusText(
        ProbeStatus(ProbeOutcome.startedOnly, DateTime(2026, 10, 30, 9, 41)),
      );
      expect(text, contains('未完成'));
      expect(text, contains('疑似崩溃'));
    });

    test('无时间时不带括号后缀', () {
      final text = probeStatusText(
        const ProbeStatus(ProbeOutcome.loaded, null),
      );
      expect(text, '上次加载成功');
    });
  });

  group('probeBlocker', () {
    test('无 Key → missingKey（优先于隐私）', () {
      expect(
        probeBlocker(hasSdkKey: false, privacyAgreed: false),
        ProbeBlocker.missingKey,
      );
      expect(
        probeBlocker(hasSdkKey: false, privacyAgreed: true),
        ProbeBlocker.missingKey,
      );
    });

    test('有 Key 未同意隐私 → privacyNotAgreed', () {
      expect(
        probeBlocker(hasSdkKey: true, privacyAgreed: false),
        ProbeBlocker.privacyNotAgreed,
      );
    });

    test('齐备 → null（可打开）', () {
      expect(probeBlocker(hasSdkKey: true, privacyAgreed: true), isNull);
    });
  });
}
