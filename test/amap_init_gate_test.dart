import 'package:flutter_test/flutter_test.dart';

import 'package:shitu/services/amap_init_gate.dart';

void main() {
  group('AmapInitGate', () {
    test('同一 Key 只执行一次：并发与后续调用都共享结果', () async {
      final gate = AmapInitGate();
      var runs = 0;
      Future<bool> runner() async {
        runs++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return true;
      }

      final results = await Future.wait([
        gate.ensure('k1', runner),
        gate.ensure('k1', runner),
        gate.ensure('k1', runner),
      ]);
      expect(results, [true, true, true]);
      expect(runs, 1);
      expect(gate.status, AmapInitStatus.ready);
      expect(gate.isReady, isTrue);

      // 已就绪后同一 Key 直接返回，不再执行。
      expect(await gate.ensure('k1', runner), isTrue);
      expect(runs, 1);
    });

    test('失败后状态为 failed 并记录原因，下一次调用可重试', () async {
      final gate = AmapInitGate();
      var attempts = 0;
      Future<bool> flaky() async {
        attempts++;
        if (attempts == 1) throw StateError('模拟原生初始化异常');
        return true;
      }

      expect(await gate.ensure('k1', flaky), isFalse);
      expect(gate.status, AmapInitStatus.failed);
      expect(gate.lastError, contains('模拟原生初始化异常'));

      expect(await gate.ensure('k1', flaky), isTrue);
      expect(gate.status, AmapInitStatus.ready);
      expect(attempts, 2);
    });

    test('runner 返回 false 也算失败，可重试', () async {
      final gate = AmapInitGate();
      expect(await gate.ensure('k1', () async => false), isFalse);
      expect(gate.status, AmapInitStatus.failed);
      expect(gate.lastError, isNotNull);
      expect(await gate.ensure('k1', () async => true), isTrue);
    });

    test('Key 变化后重新执行初始化', () async {
      final gate = AmapInitGate();
      var runs = 0;
      Future<bool> runner() async {
        runs++;
        return true;
      }

      expect(await gate.ensure('k1', runner), isTrue);
      expect(await gate.ensure('k2', runner), isTrue);
      expect(runs, 2);
      expect(gate.isReady, isTrue);
    });

    test('reset 后回到 idle 并可重新初始化', () async {
      final gate = AmapInitGate();
      await gate.ensure('k1', () async => true);
      gate.reset();
      expect(gate.status, AmapInitStatus.idle);
      var runs = 0;
      await gate.ensure('k1', () async {
        runs++;
        return true;
      });
      expect(runs, 1);
    });
  });
}
