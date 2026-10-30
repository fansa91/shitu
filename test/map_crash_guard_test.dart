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

    test('Java 侧步骤行：原样保留、step 为空、中文标签映射', () {
      final b = MapBreadcrumb.decode('java_mapview_ctor_start|1730000000456');
      expect(b, isNotNull);
      expect(b!.step, isNull);
      expect(b.wireName, 'java_mapview_ctor_start');
      expect(b.label, '原生：地图视图构造开始');
      expect(b.at.millisecondsSinceEpoch, 1730000000456);
      // 编码往返不丢信息（诊断复制/落盘重写都靠它）。
      expect(b.encode(), 'java_mapview_ctor_start|1730000000456');
      expect(MapBreadcrumb.decode('java_privacy_done|1')?.label, '原生：隐私注入完成');
      expect(MapBreadcrumb.decode('java_apikey_done|1')?.label, '原生：Key 注入完成');
      expect(MapBreadcrumb.decode('java_getmap_done|1')?.label, '原生：地图实例取得');
      expect(MapBreadcrumb.decode('java_oncreate_done|1')?.label, '原生：地图 onCreate 完成');
    });

    test('Java 异常行：java_error:<类名> 展示为「原生异常：<类名>」', () {
      final b = MapBreadcrumb.decode('java_error:UnsatisfiedLinkError|99');
      expect(b, isNotNull);
      expect(b!.step, isNull);
      expect(b.wireName, 'java_error:UnsatisfiedLinkError');
      expect(b.label, '原生异常：UnsatisfiedLinkError');
      expect(b.encode(), 'java_error:UnsatisfiedLinkError|99');
    });

    test('未登记的 Java 步骤：保留并原样展示，不被当坏行丢弃', () {
      final b = MapBreadcrumb.decode('java_future_step|7');
      expect(b, isNotNull);
      expect(b!.label, 'java_future_step');
    });

    test('整轮解析：Dart 与 Java 步骤混排时顺序与内容都保留', () {
      final raw = [
        _b(MapBreadcrumbStep.sdkInitStart, 1).encode(),
        _b(MapBreadcrumbStep.mapCreateStart, 2).encode(),
        'java_privacy_done|3',
        'java_apikey_done|4',
        'java_mapview_ctor_start|5',
      ].join('\n');
      final round = decodeBreadcrumbRound(raw);
      expect(round.map((b) => b.wireName), [
        'sdk_init_start',
        'map_create_start',
        'java_privacy_done',
        'java_apikey_done',
        'java_mapview_ctor_start',
      ]);
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
      expect(v.stoppedAt?.step, MapBreadcrumbStep.mapCreateStart);
    });

    test('停在创建回调之后、首帧之前 → 触发', () {
      final v = evaluateCrashGuard([
        _b(MapBreadcrumbStep.sdkInitStart),
        _b(MapBreadcrumbStep.sdkInitDone),
        _b(MapBreadcrumbStep.mapCreateStart),
        _b(MapBreadcrumbStep.onMapCreated),
      ]);
      expect(v.tripped, isTrue);
      expect(v.stoppedAt?.step, MapBreadcrumbStep.onMapCreated);
    });

    test('停在 SDK 初始化中 → 触发', () {
      final v = evaluateCrashGuard([_b(MapBreadcrumbStep.sdkInitStart)]);
      expect(v.tripped, isTrue);
      expect(v.stoppedAt?.step, MapBreadcrumbStep.sdkInitStart);
    });

    test('停在 Java 构造步 → 触发，停留步落到该 Java 子步骤', () {
      final v = evaluateCrashGuard([
        _b(MapBreadcrumbStep.sdkInitStart),
        _b(MapBreadcrumbStep.mapCreateStart),
        MapBreadcrumb.decode('java_privacy_done|3')!,
        MapBreadcrumb.decode('java_mapview_ctor_start|4')!,
      ]);
      expect(v.tripped, isTrue);
      expect(v.stoppedAt?.wireName, 'java_mapview_ctor_start');
      expect(v.stoppedAt?.label, '原生：地图视图构造开始');
    });

    test('最后一行是 Java 异常 → 触发，停留步带出异常类名', () {
      final v = evaluateCrashGuard([
        _b(MapBreadcrumbStep.sdkInitStart),
        _b(MapBreadcrumbStep.mapCreateStart),
        MapBreadcrumb.decode('java_mapview_ctor_start|3')!,
        MapBreadcrumb.decode('java_error:UnsatisfiedLinkError|4')!,
      ]);
      expect(v.tripped, isTrue);
      expect(v.stoppedAt?.label, '原生异常：UnsatisfiedLinkError');
    });

    test('有 Java 步骤但到过首帧 → 不触发', () {
      final v = evaluateCrashGuard([
        _b(MapBreadcrumbStep.sdkInitStart),
        _b(MapBreadcrumbStep.mapCreateStart),
        MapBreadcrumb.decode('java_getmap_done|3')!,
        _b(MapBreadcrumbStep.onMapCreated),
        _b(MapBreadcrumbStep.firstFrame),
      ]);
      expect(v.tripped, isFalse);
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
      expect(second.stoppedAt?.step, MapBreadcrumbStep.mapCreateStart);
      expect(second.previousRound.length, 3);
      expect(second.breadcrumbReport(), contains('地图创建开始'));

      // 用户点「重试真实地图」：自保清除、落盘清空，再下一轮不再触发。
      second.clearGuardForRetry();
      expect(second.guardTripped, isFalse);
      expect(sink.read(), isNull);
      final third = MapCrashGuard(sink: sink);
      expect(third.guardTripped, isFalse);
    });

    test('Java 步骤/异常行混在落盘里：下一轮读回并报出原生异常', () {
      final sink = MemoryBreadcrumbSink();
      final first = MapCrashGuard(sink: sink);
      first.markStep(MapBreadcrumbStep.sdkInitStart);
      first.markStep(MapBreadcrumbStep.sdkInitDone);
      first.markStep(MapBreadcrumbStep.mapCreateStart);
      // 模拟 Java 侧在同一文件追加打点与异常行（原生 catch 吞掉异常后
      // 进程未死、但也没有后续 Dart 步骤；或进程随后死亡——两种情况
      // 下一轮读到的文件都长这样）。
      sink.write('${sink.read()}\n'
          'java_privacy_done|100\n'
          'java_apikey_done|101\n'
          'java_mapview_ctor_start|102\n'
          'java_error:UnsatisfiedLinkError|103');

      final second = MapCrashGuard(sink: sink);
      expect(second.guardTripped, isTrue);
      expect(second.previousRound.length, 7);
      expect(second.stoppedAt?.wireName, 'java_error:UnsatisfiedLinkError');
      expect(second.breadcrumbReport(), contains('原生异常：UnsatisfiedLinkError'));
      expect(second.breadcrumbReport(), contains('原生：隐私注入完成'));
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
