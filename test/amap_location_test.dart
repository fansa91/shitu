import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shitu/models/geo_point.dart';
import 'package:shitu/models/located_fix.dart';
import 'package:shitu/services/amap_location.dart';
import 'package:shitu/services/location_guard.dart';
import 'package:shitu/services/location_runtime_status.dart';
import 'package:shitu/services/location_service.dart';
import 'package:shitu/utils/coord.dart';

Position _position(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026, 10, 30),
  accuracy: 10,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 2.5,
  speedAccuracy: 0,
);

class _MemoryBoolStore implements BoolStore {
  final Map<String, bool> values = {};

  @override
  Future<bool> read(String key) async => values[key] ?? false;

  @override
  Future<void> write(String key, bool value) async => values[key] = value;
}

/// 假高德后端：可配 init/单次的结果或异常、可配持续流。
class _FakeAmapBackend implements AmapLocationBackend {
  _FakeAmapBackend({this.onceFix, this.onceError, this.watchFactory});

  AmapRawFix? onceFix;
  Object? onceError;

  /// 持续定位流工厂（默认空流）。
  Stream<AmapRawFix> Function()? watchFactory;

  int initCalls = 0;
  int stopCalls = 0;

  @override
  Future<void> init({required String apiKey}) async {
    initCalls++;
  }

  @override
  Future<AmapRawFix> fetchOnce() async {
    final error = onceError;
    if (error != null) throw error;
    final fix = onceFix;
    if (fix == null) {
      // 模拟永不返回（首定超时场景）：挂起直到外部取消。
      await Completer<void>().future;
      throw StateError('unreachable');
    }
    return fix;
  }

  @override
  Stream<AmapRawFix> watch() {
    final factory = watchFactory;
    if (factory != null) return factory();
    return const Stream<AmapRawFix>.empty();
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

LocationService _facade({
  required _FakeAmapBackend backend,
  required LocationRoutingConfig config,
  AmapLocationGuard? guard,
  LocationRuntimeStatus? status,
  Duration amapTimeout = const Duration(seconds: 8),
}) {
  return LocationService(
    amapBackend: backend,
    guard: guard ?? AmapLocationGuard(store: _MemoryBoolStore()),
    status: status ?? LocationRuntimeStatus(),
    routingConfig: () => config,
    amapFirstFixTimeout: amapTimeout,
    isServiceEnabled: () async => true,
    checkPermission: () async => LocationPermission.whileInUse,
    requestPermission: () async => LocationPermission.whileInUse,
    fetchPosition: () async => _position(39.9, 116.39),
    positionStream: () => Stream.value(_position(39.9, 116.39)),
  );
}

LocationRoutingConfig _config({
  LocationSourceMode mode = LocationSourceMode.auto,
  String sdkKey = 'test-key',
  bool privacyAgreed = true,
  bool isAndroid = true,
}) => LocationRoutingConfig(
  mode: mode,
  sdkKey: sdkKey,
  privacyAgreed: privacyAgreed,
  isAndroid: isAndroid,
);

final _amapFix = AmapRawFix(
  point: const GeoPoint(latitude: 39.908722, longitude: 116.397499),
  at: DateTime(2026, 10, 30, 12),
  speedMps: 1.2,
);

void main() {
  group('parseAmapFix', () {
    test('成功结果：字段齐全原样解析，GCJ-02 不做任何加工', () {
      final fix = parseAmapFix({
        'latitude': 39.908722,
        'longitude': 116.397499,
        'accuracy': 18.0,
        'speed': 1.5,
        'timeMillis': 1793000000000,
        'errorCode': 0,
        'errorInfo': '',
      });
      expect(fix.point.latitude, 39.908722);
      expect(fix.point.longitude, 116.397499);
      expect(fix.accuracyMeters, 18);
      expect(fix.speedMps, 1.5);
      expect(fix.at, DateTime.fromMillisecondsSinceEpoch(1793000000000));
      expect(fix.toFix().source, LocationSource.amap);
    });

    test('bearing 解析；精度/方向经 toFix 透传到 LocatedFix', () {
      final fix = parseAmapFix({
        'latitude': 39.908722,
        'longitude': 116.397499,
        'accuracy': 18.0,
        'speed': 1.5,
        'bearing': 123.0,
        'timeMillis': 1793000000000,
        'errorCode': 0,
        'errorInfo': '',
      });
      expect(fix.bearingDegrees, 123);
      final located = fix.toFix();
      expect(located.accuracyMeters, 18);
      expect(located.bearingDegrees, 123);
    });

    test('错误码非 0 → 抛 AmapLocationException 带原生码与信息', () {
      expect(
        () => parseAmapFix({
          'latitude': 0.0,
          'longitude': 0.0,
          'errorCode': 7,
          'errorInfo': 'Key 鉴权失败',
        }),
        throwsA(
          isA<AmapLocationException>()
              .having((e) => e.code, 'code', 7)
              .having((e) => e.info, 'info', contains('鉴权')),
        ),
      );
    });

    test('坐标缺失 → 抛错，不伪造 0,0', () {
      expect(
        () => parseAmapFix({'errorCode': 0, 'errorInfo': ''}),
        throwsA(isA<AmapLocationException>()),
      );
    });

    test('速度 -1（原生无速度）→ null', () {
      final fix = parseAmapFix({
        'latitude': 30.0,
        'longitude': 120.0,
        'accuracy': 0.0,
        'speed': -1.0,
        'errorCode': 0,
        'errorInfo': '',
      });
      expect(fix.speedMps, isNull);
      expect(fix.accuracyMeters, isNull);
    });
  });

  group('decideLocationRoute 选路矩阵', () {
    test('系统档恒系统；非 Android 恒系统（即使选了高德档）', () {
      expect(
        decideLocationRoute(
          _config(mode: LocationSourceMode.system),
          guardTripped: false,
        ).useAmap,
        isFalse,
      );
      expect(
        decideLocationRoute(
          _config(isAndroid: false),
          guardTripped: false,
        ).useAmap,
        isFalse,
      );
      expect(
        decideLocationRoute(
          _config(isAndroid: false, mode: LocationSourceMode.amap),
          guardTripped: false,
        ).hardError,
        isNull,
      );
    });

    test('高德档条件不齐 → 硬失败逐项', () {
      for (final cfg in [
        _config(mode: LocationSourceMode.amap, sdkKey: ''),
        _config(mode: LocationSourceMode.amap, privacyAgreed: false),
      ]) {
        final d = decideLocationRoute(cfg, guardTripped: false);
        expect(d.useAmap, isFalse);
        expect(d.hardError, isNotNull);
      }
      final tripped = decideLocationRoute(
        _config(mode: LocationSourceMode.amap),
        guardTripped: true,
      );
      expect(tripped.hardError, isNotNull);
    });

    test('自动档条件不齐 → 静默系统 + 注记', () {
      final d = decideLocationRoute(_config(sdkKey: ''), guardTripped: false);
      expect(d.useAmap, isFalse);
      expect(d.hardError, isNull);
      expect(d.note, isNotNull);
    });

    test('条件齐备 → 走高德（两档）', () {
      expect(
        decideLocationRoute(_config(), guardTripped: false).useAmap,
        isTrue,
      );
      expect(
        decideLocationRoute(
          _config(mode: LocationSourceMode.amap),
          guardTripped: false,
        ).useAmap,
        isTrue,
      );
    });
  });

  group('LocationService 高德选路与回落', () {
    test('自动档高德成功：结果带 amap 标记且坐标原值不转换', () async {
      final backend = _FakeAmapBackend(onceFix: _amapFix);
      final status = LocationRuntimeStatus();
      final service = _facade(
        backend: backend,
        config: _config(),
        status: status,
      );
      final fix = await service.currentFix();
      expect(backend.initCalls, 1);
      expect(fix.source, LocationSource.amap);
      // 高德原生 GCJ-02：若被再转一次，坐标会偏出几十米——必须原样。
      expect(fix.point, _amapFix.point);
      expect(status.activeSource, LocationSource.amap);
    });

    test('自动档高德抛错 → 回落系统（转换照旧）并记注记', () async {
      final backend = _FakeAmapBackend(
        onceError: const AmapLocationException(12, '缺少定位权限'),
      );
      final status = LocationRuntimeStatus();
      final service = _facade(
        backend: backend,
        config: _config(),
        status: status,
      );
      final fix = await service.currentFix();
      expect(fix.source, LocationSource.system);
      expect(
        fix.point,
        wgs84ToGcj02(const GeoPoint(latitude: 39.9, longitude: 116.39)),
      );
      expect(status.activeSource, LocationSource.system);
      expect(status.note, contains('自动改用系统定位'));
    });

    test('自动档高德首定超时（挂起）→ 回落系统', () async {
      final backend = _FakeAmapBackend(); // onceFix 为 null → 挂起
      final service = _facade(
        backend: backend,
        config: _config(),
        amapTimeout: const Duration(milliseconds: 60),
      );
      final fix = await service.currentFix();
      expect(fix.source, LocationSource.system);
    });

    test('自动档无 Key → 不碰高德，直接系统', () async {
      final backend = _FakeAmapBackend(onceFix: _amapFix);
      final service = _facade(
        backend: backend,
        config: _config(sdkKey: ''),
      );
      final fix = await service.currentFix();
      expect(backend.initCalls, 0);
      expect(fix.source, LocationSource.system);
    });

    test('高德档失败 → 硬抛 LocationException 不回落', () async {
      final backend = _FakeAmapBackend(
        onceError: const AmapLocationException(7, 'Key 鉴权失败'),
      );
      final service = _facade(
        backend: backend,
        config: _config(mode: LocationSourceMode.amap),
      );
      await expectLater(
        service.currentFix(),
        throwsA(
          isA<LocationException>().having(
            (e) => e.message,
            'message',
            contains('鉴权'),
          ),
        ),
      );
    });

    test('高德档无 Key → 硬抛且不调用后端', () async {
      final backend = _FakeAmapBackend(onceFix: _amapFix);
      final service = _facade(
        backend: backend,
        config: _config(mode: LocationSourceMode.amap, sdkKey: ''),
      );
      await expectLater(
        service.currentFix(),
        throwsA(isA<LocationException>()),
      );
      expect(backend.initCalls, 0);
    });

    test('守卫跳闸 + 自动档 → 系统；成功一次后标记清除不跳闸', () async {
      final store = _MemoryBoolStore();
      final guard = AmapLocationGuard(store: store);
      final backend = _FakeAmapBackend(onceFix: _amapFix);
      final service = _facade(
        backend: backend,
        config: _config(),
        guard: guard,
      );
      final fix = await service.currentFix();
      expect(fix.source, LocationSource.amap);
      // 首个成功结果应清掉「进行中」标记：模拟重启结算不应跳闸。
      final nextLaunch = AmapLocationGuard(store: store);
      expect(await nextLaunch.settleOnLaunch(), isFalse);
      expect(await nextLaunch.isTripped(), isFalse);
    });

    test('持续流：高德首结果前报错（自动档）→ 整体切系统流', () async {
      final backend = _FakeAmapBackend(
        watchFactory: () =>
            Stream<AmapRawFix>.error(const AmapLocationException(4, '网络异常')),
      );
      final service = _facade(backend: backend, config: _config());
      final fixes = await service.followFixStream().toList();
      expect(fixes, isNotEmpty);
      expect(fixes.first.source, LocationSource.system);
    });

    test('持续流：高德出结果 → 标记 amap 且原值直出', () async {
      final backend = _FakeAmapBackend(
        watchFactory: () => Stream.value(_amapFix),
      );
      final service = _facade(backend: backend, config: _config());
      final fixes = await service.followFixStream().toList();
      expect(fixes.single.source, LocationSource.amap);
      expect(fixes.single.point, _amapFix.point);
    });
  });

  group('AmapLocationGuard 守卫', () {
    test('begin 后未成功（模拟崩溃）→ 下次启动结算跳闸，tryBegin 拒绝', () async {
      final store = _MemoryBoolStore();
      final run1 = AmapLocationGuard(store: store);
      expect(await run1.tryBegin(), isTrue);
      // 进程「死」在这里：没有 markSuccess。
      final run2 = AmapLocationGuard(store: store);
      expect(await run2.settleOnLaunch(), isTrue);
      expect(await run2.isTripped(), isTrue);
      expect(await run2.tryBegin(), isFalse);
    });

    test('begin 后成功 → 结算不跳闸', () async {
      final store = _MemoryBoolStore();
      final run1 = AmapLocationGuard(store: store);
      expect(await run1.tryBegin(), isTrue);
      await run1.markSuccess();
      final run2 = AmapLocationGuard(store: store);
      expect(await run2.settleOnLaunch(), isFalse);
      expect(await run2.isTripped(), isFalse);
      expect(await run2.tryBegin(), isTrue);
    });

    test('resetByUser 清除跳闸，可再次 begin', () async {
      final store = _MemoryBoolStore();
      final guard = AmapLocationGuard(store: store);
      await guard.tryBegin();
      await guard.settleOnLaunch();
      expect(await guard.isTripped(), isTrue);
      await guard.resetByUser();
      expect(await guard.isTripped(), isFalse);
      expect(await guard.tryBegin(), isTrue);
    });

    test('无残留标记时结算不动作', () async {
      final guard = AmapLocationGuard(store: _MemoryBoolStore());
      expect(await guard.settleOnLaunch(), isFalse);
    });
  });
}
