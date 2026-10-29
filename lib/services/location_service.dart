import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/geo_point.dart';
import '../utils/coord.dart';

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

/// 设备定位服务：基于 geolocator。
///
/// 系统返回 WGS-84，进 App 前统一用 [wgs84ToGcj02] 转 GCJ-02。
/// 构造函数的函数参数是单测注入点，生产代码用默认值（Geolocator 静态方法）。
class LocationService {
  LocationService({
    Future<bool> Function()? isServiceEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<Position> Function()? fetchPosition,
    Stream<Position> Function()? positionStream,
  })  : _isServiceEnabled =
            isServiceEnabled ?? Geolocator.isLocationServiceEnabled,
        _checkPermission = checkPermission ?? Geolocator.checkPermission,
        _requestPermission =
            requestPermission ?? Geolocator.requestPermission,
        _fetchPosition = fetchPosition ??
            (() => Geolocator.getCurrentPosition(
                  locationSettings: const LocationSettings(
                    accuracy: LocationAccuracy.high,
                    timeLimit: Duration(seconds: 12),
                  ),
                )),
        _positionStream = positionStream ??
            (() => Geolocator.getPositionStream(
                  locationSettings: const LocationSettings(
                    accuracy: LocationAccuracy.high,
                    distanceFilter: 5,
                  ),
                ));

  final Future<bool> Function() _isServiceEnabled;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final Future<Position> Function() _fetchPosition;
  final Stream<Position> Function() _positionStream;

  /// 确保定位可用（服务开 + 已授权），否则抛带中文文案的 [LocationException]。
  Future<void> ensureReady() async {
    bool enabled;
    try {
      enabled = await _isServiceEnabled();
    } catch (_) {
      throw const LocationException(
        LocationErrorKind.unsupported,
        '当前设备不支持定位',
      );
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

  GeoPoint _toGcj02(Position p) => wgs84ToGcj02(
        GeoPoint(latitude: p.latitude, longitude: p.longitude),
      );

  /// 取当前位置（GCJ-02）。失败抛 [LocationException]，绝不静默。
  Future<GeoPoint> currentLocation() async {
    await ensureReady();
    try {
      return _toGcj02(await _fetchPosition());
    } on TimeoutException {
      throw const LocationException(
        LocationErrorKind.timeout,
        '定位超时：GPS 信号弱，请到开阔处重试',
      );
    } catch (e) {
      if (e is LocationException) rethrow;
      throw const LocationException(
        LocationErrorKind.unknown,
        '定位失败，请稍后重试',
      );
    }
  }

  /// 持续位置更新（GCJ-02）。调用前应先 [currentLocation] 成功过一次，
  /// 保证权限流程已走完；流内错误会以 [LocationException] 形式透出。
  Stream<GeoPoint> followStream() {
    return _positionStream().map(_toGcj02).handleError((Object e) {
      if (e is TimeoutException) {
        throw const LocationException(
          LocationErrorKind.timeout,
          '定位超时：GPS 信号弱',
        );
      }
      throw const LocationException(
        LocationErrorKind.unknown,
        '定位中断，请重试',
      );
    });
  }

  Future<bool> openAppSettings() => Geolocator.openAppSettings();
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
