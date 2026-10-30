import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/geo_point.dart';
import '../models/located_fix.dart';
import '../utils/coord.dart';
import 'amap_location.dart';
import 'location_guard.dart';
import 'location_runtime_status.dart';
import 'settings_service.dart';

/// 定位失败类型，UI 据此给出不同的中文引导（开服务 / 授权 / 去设置）。
enum LocationErrorKind {
  /// 系统定位服务未开启。
  serviceDisabled,

  /// 用户拒绝了本次授权（仍可再次请求）。
  permissionDenied,

  /// 权限被永久拒绝，只能去系统设置里改。
  permissionDeniedForever,

  /// 取位置超时（信号差 / 室内无 GPS）。
  timeout,

  /// 当前平台不支持定位（如无定位实现的桌面端）。
  unsupported,

  unknown,
}

/// 定位失败（message 均为面向用户的中文文案，UI 可直接展示）。
class LocationException implements Exception {
  const LocationException(this.kind, this.message);

  final LocationErrorKind kind;
  final String message;

  /// 是否适合在提示旁给出「去设置」按钮。
  bool get needsSettings =>
      kind == LocationErrorKind.permissionDeniedForever ||
      kind == LocationErrorKind.serviceDisabled;

  @override
  String toString() => message;
}

/// 跟随锁定状态机（纯逻辑，供单测）：
/// 点定位按钮锁定；用户手动拖图后解锁；再次点定位重新锁定。
class FollowLock {
  bool _following = false;

  bool get following => _following;

  /// 点定位按钮 / 定位成功：进入跟随。
  void lock() => _following = true;

  /// 用户手动拖动地图：解除跟随。
  void unlockByUserGesture() => _following = false;

  /// 无条件解除（如页面销毁、切换到 POI 详情）。
  void unlock() => _following = false;
}

/// 选路决策的输入快照（纯数据）：定位源模式 + SDK Key + 隐私同意
/// + 平台 + 守卫状态。由 SettingsService 读出或单测直接构造。
class LocationRoutingConfig {
  const LocationRoutingConfig({
    required this.mode,
    required this.sdkKey,
    required this.privacyAgreed,
    required this.isAndroid,
  });

  final LocationSourceMode mode;
  final String sdkKey;
  final bool privacyAgreed;

  /// 高德定位桥只有 Android 实现；其它平台恒走系统定位。
  final bool isAndroid;

  bool get hasKey => sdkKey.trim().isNotEmpty;
}

/// 选路结果（纯逻辑产物，见 [decideLocationRoute]）。
class LocationDecision {
  const LocationDecision._({required this.useAmap, this.hardError, this.note});

  /// true = 先走高德定位；false = 走系统定位。
  final bool useAmap;

  /// 非空 = 硬失败（仅手动选高德且条件不齐时）：直接抛出，不回落。
  final LocationException? hardError;

  /// 走系统时的补充说明（供运行时状态展示），无则为 null。
  final String? note;
}

/// 选路决策（纯函数，供单测）：三档模式 × 条件齐备与否 → 路线。
/// - 系统档 / 非 Android：恒系统；
/// - 高德档：条件不齐（无 Key / 未同意隐私 / 守卫跳闸）→ 硬失败，
///   如实报错让用户去补，不静默回落（用户明确选了高德）；
/// - 自动档：条件不齐 → 静默走系统（附注记）；齐备 → 先高德，
///   失败或首定超时再回落（回落逻辑在 LocationService）。
LocationDecision decideLocationRoute(
  LocationRoutingConfig config, {
  required bool guardTripped,
}) {
  const system = LocationDecision._(useAmap: false);
  if (config.mode == LocationSourceMode.system) return system;
  if (!config.isAndroid) return system;
  if (config.mode == LocationSourceMode.amap) {
    if (!config.hasKey) {
      return const LocationDecision._(
        useAmap: false,
        hardError: LocationException(
          LocationErrorKind.unknown,
          '已选高德定位，但还没填高德 Android SDK Key（设置 → 高德定位）',
        ),
      );
    }
    if (!config.privacyAgreed) {
      return const LocationDecision._(
        useAmap: false,
        hardError: LocationException(
          LocationErrorKind.unknown,
          '已选高德定位，但尚未同意高德隐私政策（设置 → 高德定位）',
        ),
      );
    }
    if (guardTripped) {
      return const LocationDecision._(
        useAmap: false,
        hardError: LocationException(
          LocationErrorKind.unknown,
          '高德定位上次启动异常，已被守卫跳过；如需重试请去设置 → 高德定位点「重试高德定位」',
        ),
      );
    }
    return const LocationDecision._(useAmap: true);
  }
  // 自动档：条件不齐静默走系统。
  if (!config.hasKey) {
    return const LocationDecision._(
      useAmap: false,
      note: '未填高德 SDK Key，当前用系统定位',
    );
  }
  if (!config.privacyAgreed) {
    return const LocationDecision._(useAmap: false, note: '未同意高德隐私政策，当前用系统定位');
  }
  if (guardTripped) {
    return const LocationDecision._(useAmap: false, note: '高德定位已被守卫跳过，当前用系统定位');
  }
  return const LocationDecision._(useAmap: true);
}

/// 设备定位门面：双后端——高德定位（Android，GCJ-02 直出、国内
/// 网络定位强）+ 系统定位（geolocator，WGS-84 转 GCJ-02）。
/// 选路/回落规则见 [decideLocationRoute]；消费接口
/// （[currentLocation] / [followStream] / [followFixStream] /
/// [ensureReady]）与单后端时代完全一致，跟随/导航无感切换。
///
/// 坐标纪律：高德结果带 [LocationSource.amap] 标记且**不做转换**；
/// 系统结果照旧走 [wgs84ToGcj02]。
class LocationService {
  LocationService({
    this.settings,
    AmapLocationBackend? amapBackend,
    AmapLocationGuard? guard,
    LocationRuntimeStatus? status,
    LocationRoutingConfig Function()? routingConfig,
    this.amapFirstFixTimeout = const Duration(seconds: 8),
    // —— 系统后端（geolocator）的注入点，单测用；生产用默认值 ——
    Future<bool> Function()? isServiceEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<Position> Function()? fetchPosition,
    Stream<Position> Function()? positionStream,
  }) : _amap = amapBackend ?? ChannelAmapLocationBackend(),
       _guard = guard ?? AmapLocationGuard(),
       _status = status ?? LocationRuntimeStatus.instance,
       _routingConfigOverride = routingConfig,
       _isServiceEnabled =
           isServiceEnabled ?? Geolocator.isLocationServiceEnabled,
       _checkPermission = checkPermission ?? Geolocator.checkPermission,
       _requestPermission = requestPermission ?? Geolocator.requestPermission,
       _fetchPosition =
           fetchPosition ??
           (() => Geolocator.getCurrentPosition(
             locationSettings: const LocationSettings(
               accuracy: LocationAccuracy.high,
               timeLimit: Duration(seconds: 12),
             ),
           )),
       _positionStream =
           positionStream ??
           (() => Geolocator.getPositionStream(
             locationSettings: const LocationSettings(
               accuracy: LocationAccuracy.high,
               distanceFilter: 5,
             ),
           ));

  /// 设置来源（选路读 Key/隐私/模式）；单测可改用 routingConfig 注入。
  final SettingsService? settings;

  /// 高德首定超时：自动档超过此时长未出结果即回落系统（默认 8 秒）。
  final Duration amapFirstFixTimeout;

  final AmapLocationBackend _amap;
  final AmapLocationGuard _guard;
  final LocationRuntimeStatus _status;
  final LocationRoutingConfig Function()? _routingConfigOverride;

  final Future<bool> Function() _isServiceEnabled;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final Future<Position> Function() _fetchPosition;
  final Stream<Position> Function() _positionStream;

  LocationRoutingConfig _routingConfig() {
    final override = _routingConfigOverride;
    if (override != null) return override();
    final s = settings;
    return LocationRoutingConfig(
      mode: s?.locationSourceMode ?? LocationSourceMode.auto,
      sdkKey: s?.amapSdkAndroidKey ?? '',
      privacyAgreed: s?.privacyAgreed ?? false,
      isAndroid: defaultTargetPlatform == TargetPlatform.android,
    );
  }

  /// 确保定位可用（服务开 + 已授权），否则抛带中文文案的 [LocationException]。
  /// 两个后端共用这套前置（高德 SDK 同样需要系统定位服务与权限）。
  Future<void> ensureReady() async {
    bool enabled;
    try {
      enabled = await _isServiceEnabled();
    } catch (_) {
      throw const LocationException(LocationErrorKind.unsupported, '当前设备不支持定位');
    }
    if (!enabled) {
      throw const LocationException(
        LocationErrorKind.serviceDisabled,
        '系统定位服务未开启，请先在系统设置中打开定位',
      );
    }
    var permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _requestPermission();
    }
    switch (permission) {
      case LocationPermission.denied:
        throw const LocationException(
          LocationErrorKind.permissionDenied,
          '没有定位权限，无法获取你的位置（可在弹窗中允许，或去系统设置开启）',
        );
      case LocationPermission.deniedForever:
        throw const LocationException(
          LocationErrorKind.permissionDeniedForever,
          '定位权限已被拒绝，请去系统设置中为识途开启定位权限',
        );
      case LocationPermission.whileInUse:
      case LocationPermission.always:
      case LocationPermission.unableToDetermine:
        return;
    }
  }

  GeoPoint _toGcj02(Position p) =>
      wgs84ToGcj02(GeoPoint(latitude: p.latitude, longitude: p.longitude));

  LocatedFix _systemFix(Position p) => LocatedFix(
    point: _toGcj02(p),
    at: p.timestamp,
    speedMps: p.speed >= 0 ? p.speed : null,
    source: LocationSource.system,
  );

  String _describeAmapError(Object e) {
    if (e is AmapLocationException) return e.info;
    if (e is TimeoutException) return '首定超时';
    return '未知错误';
  }

  /// 取当前位置（GCJ-02）。失败抛 [LocationException]，绝不静默。
  Future<GeoPoint> currentLocation() async => (await currentFix()).point;

  /// 取当前位置（含来源/速度/时刻）：选路与回落都在这里。
  /// 高德是否「够格成为候选」：只有够格时才需要查守卫状态
  /// （不够格恒走系统，也免了纯系统用户的存储读取）。
  bool _amapCandidate(LocationRoutingConfig config) =>
      config.mode != LocationSourceMode.system &&
      config.isAndroid &&
      config.hasKey &&
      config.privacyAgreed;

  Future<LocatedFix> currentFix() async {
    await ensureReady();
    final config = _routingConfig();
    final decision = decideLocationRoute(
      config,
      guardTripped: _amapCandidate(config) ? await _guard.isTripped() : false,
    );
    if (decision.hardError != null) throw decision.hardError!;
    if (!decision.useAmap) {
      final fix = await _fetchSystemFix();
      if (decision.note != null) {
        _status.reportFallback(decision.note!);
      } else {
        _status.reportSuccess(LocationSource.system);
      }
      return fix;
    }
    // —— 高德路径 ——
    if (!await _guard.tryBegin()) {
      // 决策后守卫状态刚变化（极少）：按跳闸处理。
      if (config.mode == LocationSourceMode.amap) {
        throw const LocationException(
          LocationErrorKind.unknown,
          '高德定位已被守卫跳过，请去设置 → 高德定位点「重试高德定位」',
        );
      }
      final fix = await _fetchSystemFix();
      _status.reportFallback('高德定位已被守卫跳过，当前用系统定位');
      return fix;
    }
    try {
      await _amap.init(apiKey: config.sdkKey);
      final raw = await _amap.fetchOnce().timeout(amapFirstFixTimeout);
      await _guard.markSuccess();
      _status.reportSuccess(LocationSource.amap);
      return raw.toFix();
    } catch (e) {
      if (config.mode == LocationSourceMode.amap) {
        throw LocationException(
          LocationErrorKind.unknown,
          '高德定位失败：${_describeAmapError(e)}',
        );
      }
      final fix = await _fetchSystemFix();
      _status.reportFallback('高德定位失败，已自动改用系统定位');
      return fix;
    }
  }

  Future<LocatedFix> _fetchSystemFix() async {
    try {
      return _systemFix(await _fetchPosition());
    } on TimeoutException {
      throw const LocationException(
        LocationErrorKind.timeout,
        '定位超时：GPS 信号弱，请到开阔处重试',
      );
    } catch (e) {
      if (e is LocationException) rethrow;
      throw const LocationException(LocationErrorKind.unknown, '定位失败，请稍后重试');
    }
  }

  Stream<Position> _systemRawStream() {
    return _positionStream().handleError((Object e) {
      if (e is TimeoutException) {
        throw const LocationException(
          LocationErrorKind.timeout,
          '定位超时：GPS 信号弱',
        );
      }
      throw const LocationException(LocationErrorKind.unknown, '定位中断，请重试');
    });
  }

  /// 持续位置更新（GCJ-02 点）。调用前应先 [currentLocation] 成功过
  /// 一次，保证权限流程已走完；流内错误以 [LocationException] 透出。
  Stream<GeoPoint> followStream() => followFixStream().map((fix) => fix.point);

  /// 带来源/速度/时刻的持续定位流（导航跟随 / 轨迹记录用）。
  ///
  /// 选路同 [currentFix]：自动档先试高德流，首个结果到达即锁定
  /// 高德；首定超时（默认 8 秒）或流报错则整体切换到系统流。
  /// 高德档流报错直接透出；系统档只走系统流。
  Stream<LocatedFix> followFixStream() async* {
    final config = _routingConfig();
    final decision = decideLocationRoute(
      config,
      guardTripped: _amapCandidate(config) ? await _guard.isTripped() : false,
    );
    if (decision.hardError != null) throw decision.hardError!;
    if (!decision.useAmap) {
      if (decision.note != null) _status.reportFallback(decision.note!);
      yield* _systemRawStream().map(_systemFix);
      return;
    }
    if (!await _guard.tryBegin()) {
      if (config.mode == LocationSourceMode.amap) {
        throw const LocationException(
          LocationErrorKind.unknown,
          '高德定位已被守卫跳过，请去设置 → 高德定位点「重试高德定位」',
        );
      }
      _status.reportFallback('高德定位已被守卫跳过，当前用系统定位');
      yield* _systemRawStream().map(_systemFix);
      return;
    }
    try {
      await _amap.init(apiKey: config.sdkKey);
    } catch (e) {
      if (config.mode == LocationSourceMode.amap) {
        throw LocationException(
          LocationErrorKind.unknown,
          '高德定位初始化失败：${_describeAmapError(e)}',
        );
      }
      _status.reportFallback('高德定位初始化失败，已自动改用系统定位');
      yield* _systemRawStream().map(_systemFix);
      return;
    }

    // 高德流：首个结果前可回落（自动档），锁定后错误按模式处理。
    var locked = false;
    try {
      await for (final raw in _amap.watch().timeout(
        amapFirstFixTimeout,
        onTimeout: (sink) =>
            sink.addError(TimeoutException("高德定位首定超时", amapFirstFixTimeout)),
      )) {
        if (!locked) {
          locked = true;
          await _guard.markSuccess();
          _status.reportSuccess(LocationSource.amap);
        }
        yield raw.toFix();
      }
    } catch (e) {
      if (!locked && config.mode == LocationSourceMode.auto) {
        await _amap.stop();
        _status.reportFallback('高德定位失败，已自动改用系统定位');
        yield* _systemRawStream().map(_systemFix);
        return;
      }
      if (e is AmapLocationException) {
        throw LocationException(LocationErrorKind.unknown, '高德定位中断：${e.info}');
      }
      throw const LocationException(LocationErrorKind.unknown, '定位中断，请重试');
    } finally {
      await _amap.stop();
    }
  }

  Future<bool> openAppSettings() => Geolocator.openAppSettings();
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
