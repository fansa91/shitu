import 'package:flutter_test/flutter_test.dart';

import 'package:shitu/services/map_crash_guard.dart';

MapBreadcrumb _b(MapBreadcrumbStep step, [int millis = 0]) =>
    MapBreadcrumb(step, DateTime.fromMillisecondsSinceEpoch(millis));

void main() {
  group('面包屑编解码', () {
    test('encode/decode 往返一致', () {
      final b = _b(MapBreadcrumbStep.mapCreateStart, 1730000000123);
      final back = MapBreadcrumb.decode(b.encode());
      expect(back?.step, MapBreadcrumbStep.mapCreateStart);
      expect(back?.at.millisecondsSinceEpoch, 1730000000123);
    });

    test('整轮解析：坏行跳过，不整体失败', () {
      final raw = [
        _b(MapBreadcrumbStep.sdkInitStart, 1).encode(),
        'garbage-line',
        'unknown_step|42',
        _b(MapBreadcrumbStep.mapCreateStart, 2).encode(),
        '',
      ].join('\n');
      final round = decodeBreadcrumbRound(raw);
      expect(round.map((b) => b.step), [
        MapBreadcrumbStep.sdkInitStart,
        MapBreadcrumbStep.mapCreateStart,
      ]);
      expect(decodeBreadcrumbRound(null), isEmpty);
      expect(decodeBreadcrumbRound(''), isEmpty);
    });
  });

  group('evaluateCrashGuard 自保判定', () {
    test('空轮次不触发', () {
      final v = evaluateCrashGuard(const []);
      expect(v.tripped, isFalse);
      expect(v.stoppedAt, isNull);
    });

    test('停在地图创建开始（原生建图窗口）→ 触发，停留步正确', () {
      final v = evaluateCrashGuard([
        _b(MapBreadcrumbStep.sdkInitStart),
        _b(MapBreadcrumbStep.sdkInitDone),
        _b(MapBreadcrumbStep.mapCreateStart),
      ]);
      expect(v.tripped, isTrue);
      expect(v.stoppedAt, MapBreadcrumbStep.mapCreateStart);
    });

    test('停在创建回调之后、首帧之前 → 触发', () {
      final v = evaluateCrashGuard([
        _b(MapBreadcrumbStep.sdkInitStart),
        _b(MapBreadcrumbStep.sdkInitDone),
        _b(MapBreadcrumbStep.mapCreateStart),
        _b(MapBreadcrumbStep.onMapCreated),
      ]);
      expect(v.tripped, isTrue);
      expect(v.stoppedAt, MapBreadcrumbStep.onMapCreated);
    });

    test('停在 SDK 初始化中 → 触发', () {
      final v = evaluateCrashGuard([_b(MapBreadcrumbStep.sdkInitStart)]);
      expect(v.tripped, isTrue);
      expect(v.stoppedAt, MapBreadcrumbStep.sdkInitStart);
    });

    test('到过首帧 → 不触发（之后被系统杀掉不算建图崩溃）', () {
      final v = evaluateCrashGuard([
        _b(MapBreadcrumbStep.sdkInitStart),
        _b(MapBreadcrumbStep.sdkInitDone),
        _b(MapBreadcrumbStep.mapCreateStart),
        _b(MapBreadcrumbStep.onMapCreated),
        _b(MapBreadcrumbStep.firstFrame),
      ]);
      expect(v.tripped, isFalse);
    });

    test('有正常销毁标记 → 不触发', () {
      final v = evaluateCrashGuard([
        _b(MapBreadcrumbStep.sdkInitStart),
        _b(MapBreadcrumbStep.sdkInitDone),
        _b(MapBreadcrumbStep.mapDisposedClean),
      ]);
      expect(v.tripped, isFalse);
    });
  });

  group('MapCrashGuard 跨启动流程（内存介质模拟）', () {
    test('上一轮死在建图：下一轮触发自保，重试清除后恢复', () {
      final sink = MemoryBreadcrumbSink();
      // 第一轮：建图链路走到 map_create_start 后「进程死亡」（不再落盘）。
      final first = MapCrashGuard(sink: sink);
      expect(first.guardTripped, isFalse);
      first.markStep(MapBreadcrumbStep.sdkInitStart);
      first.markStep(MapBreadcrumbStep.sdkInitDone);
      first.markStep(MapBreadcrumbStep.mapCreateStart);

      // 第二轮启动：应触发自保并报出停留步。
      final second = MapCrashGuard(sink: sink);
      expect(second.guardTripped, isTrue);
      expect(second.stoppedAt, MapBreadcrumbStep.mapCreateStart);
      expect(second.previousRound.length, 3);
      expect(second.breadcrumbReport(), contains('地图创建开始'));

      // 用户点「重试真实地图」：自保清除、落盘清空，再下一轮不再触发。
      second.clearGuardForRetry();
      expect(second.guardTripped, isFalse);
      expect(sink.read(), isNull);
      final third = MapCrashGuard(sink: sink);
      expect(third.guardTripped, isFalse);
    });

    test('健康一轮（首帧+正常销毁）：下一轮不触发', () {
      final sink = MemoryBreadcrumbSink();
      final first = MapCrashGuard(sink: sink);
      for (final s in MapBreadcrumbStep.values) {
        first.markStep(s);
      }
      final second = MapCrashGuard(sink: sink);
      expect(second.guardTripped, isFalse);
      expect(second.stoppedAt, isNull);
    });

    test('新一轮以 sdk_init_start 开始时清掉上一轮记录', () {
      final sink = MemoryBreadcrumbSink();
      final guard = MapCrashGuard(sink: sink);
      guard.markStep(MapBreadcrumbStep.sdkInitStart);
      guard.markStep(MapBreadcrumbStep.mapCreateStart);
      guard.markStep(MapBreadcrumbStep.sdkInitStart); // 第二轮开始
      final round = decodeBreadcrumbRound(sink.read());
      expect(round.map((b) => b.step), [MapBreadcrumbStep.sdkInitStart]);
    });
  });
}
