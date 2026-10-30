import 'package:flutter_test/flutter_test.dart';
import 'package:shitu/services/native_map_probe.dart';

void main() {
  group('parseProbeStatus', () {
    test('无记录 → neverTried', () {
      final s = parseProbeStatus(null, null);
      expect(s.outcome, ProbeOutcome.neverTried);
      expect(s.at, isNull);
      expect(s.step, isNull);
    });

    test('空字符串 → neverTried（留痕损坏不误判）', () {
      expect(parseProbeStatus('', 1).outcome, ProbeOutcome.neverTried);
    });

    test('loaded + 时间戳 → loaded 且带时间', () {
      const millis = 1793400000000;
      final s = parseProbeStatus('loaded', millis);
      expect(s.outcome, ProbeOutcome.loaded);
      expect(s.at, DateTime.fromMillisecondsSinceEpoch(millis));
      expect(s.step, isNull);
    });

    test('started → stoppedAtStep 且 step=started', () {
      final s = parseProbeStatus('started', 1793400000000);
      expect(s.outcome, ProbeOutcome.stoppedAtStep);
      expect(s.step, 'started');
      expect(s.at, isNotNull);
    });

    test('中间步骤原样保留（分步留痕判读死点）', () {
      for (final step in [
        'privacy_done',
        'key_set',
        'view_created',
        'oncreate_done',
        'onresume_done',
      ]) {
        final s = parseProbeStatus(step, 1793400000000);
        expect(s.outcome, ProbeOutcome.stoppedAtStep, reason: step);
        expect(s.step, step, reason: step);
      }
    });

    test('有状态无时间戳：outcome 照常、时间为 null', () {
      final s = parseProbeStatus('loaded', null);
      expect(s.outcome, ProbeOutcome.loaded);
      expect(s.at, isNull);
    });
  });

  group('probeStatusText', () {
    test('neverTried 文案标注导航 SDK 9.8.3', () {
      final text = probeStatusText(
        const ProbeStatus(ProbeOutcome.neverTried, null),
      );
      expect(text, contains('尚未试过'));
      expect(text, contains('导航 SDK 9.8.3'));
    });

    test('loaded 文案带成功字样', () {
      final text = probeStatusText(
        ProbeStatus(ProbeOutcome.loaded, DateTime(2026, 10, 30, 14, 5)),
      );
      expect(text, contains('上次加载成功'));
      expect(text, contains('10月30日'));
      expect(text, contains('14:05'));
    });

    test('stoppedAtStep 文案报停在哪一步', () {
      final text = probeStatusText(
        ProbeStatus(
          ProbeOutcome.stoppedAtStep,
          DateTime(2026, 10, 30, 9, 41),
          step: 'view_created',
        ),
      );
      expect(text, contains('上次停在：view_created'));
      expect(text, contains('疑似崩溃'));
      expect(text, contains('10月30日'));
    });

    test('无时间时不带括号后缀', () {
      final text = probeStatusText(
        const ProbeStatus(ProbeOutcome.loaded, null),
      );
      expect(text, '上次加载成功');
      final stopped = probeStatusText(
        const ProbeStatus(
          ProbeOutcome.stoppedAtStep,
          null,
          step: 'started',
        ),
      );
      expect(stopped, '上次停在：started——疑似崩溃');
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
