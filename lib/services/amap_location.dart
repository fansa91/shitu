import 'dart:async';

import 'package:flutter/services.dart';

import '../models/geo_point.dart';
import '../models/located_fix.dart';

/// 高德定位一次采样（原生返回值）：坐标即 GCJ-02 **原值**，
/// 调用方禁止再做任何坐标转换（见 [LocationSource.amap]）。
class AmapRawFix {
  const AmapRawFix({
    required this.point,
    required this.at,
    this.accuracyMeters,
    this.speedMps,
    this.bearingDegrees,
  });

  /// 位置（GCJ-02，高德定位原生输出）。
  final GeoPoint point;

  /// 采样时刻（原生时间戳）。
  final DateTime at;

  /// 精度半径（米）；原生未提供时为 null。
  final double? accuracyMeters;

  /// 速度（米/秒）；原生未提供（-1）时为 null。
  final double? speedMps;

  /// 行进方向（度，0=正北、顺时针）；原生未提供时为 null。
  final double? bearingDegrees;

  LocatedFix toFix() => LocatedFix(
    point: point,
    at: at,
    speedMps: speedMps,
    accuracyMeters: accuracyMeters,
    bearingDegrees: bearingDegrees,
    source: LocationSource.amap,
  );
}

/// 高德定位失败：[code] 是原生错误码（AMapLocation.getErrorCode，
/// 如 12=缺少定位权限、7=Key 鉴权失败），[info] 是原生错误信息。
class AmapLocationException implements Exception {
  const AmapLocationException(this.code, this.info);

  final int code;
  final String info;

  @override
  String toString() => '高德定位错误 $code：$info';
}

/// 解析桥返回的一条定位 map（纯函数，供单测）：
/// errorCode != 0 或字段缺失 → 抛 [AmapLocationException]。
AmapRawFix parseAmapFix(Map<Object?, Object?> raw) {
  final errorCode = (raw['errorCode'] as num?)?.toInt() ?? -1;
  final errorInfo = raw['errorInfo'] as String? ?? '';
  final lat = (raw['latitude'] as num?)?.toDouble();
  final lng = (raw['longitude'] as num?)?.toDouble();
  if (errorCode != 0 || lat == null || lng == null) {
    throw AmapLocationException(
      errorCode,
      errorInfo.isNotEmpty ? errorInfo : '原生未返回有效坐标',
    );
  }
  final accuracy = (raw['accuracy'] as num?)?.toDouble();
  final speed = (raw['speed'] as num?)?.toDouble();
  final bearing = (raw['bearing'] as num?)?.toDouble();
  final timeMillis = (raw['timeMillis'] as num?)?.toInt();
  return AmapRawFix(
    point: GeoPoint(latitude: lat, longitude: lng),
    at: timeMillis == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(timeMillis),
    accuracyMeters: (accuracy != null && accuracy > 0) ? accuracy : null,
    speedMps: (speed != null && speed >= 0) ? speed : null,
    bearingDegrees: bearing,
  );
}

/// 高德定位后端接口：LocationService 门面依赖它选路/回落，
/// 单测注入假实现，真实现是 [ChannelAmapLocationBackend]。
abstract interface class AmapLocationBackend {
  /// 初始化：隐私同意声明 + 设置 Key + 构造原生客户端。
  /// 必须在用户已同意隐私（SettingsService.privacyAgreed）后调用。
  Future<void> init({required String apiKey});

  /// 单次定位（高精度）。失败抛 [AmapLocationException]。
  Future<AmapRawFix> fetchOnce();

  /// 持续定位流。错误以 [AmapLocationException] 事件透出。
  Stream<AmapRawFix> watch();

  /// 停止持续定位（watch 订阅取消时由门面调用）。
  Future<void> stop();
}

/// 基于 MethodChannel/EventChannel 的高德定位后端：
/// 通道与原生桥（android/.../AmapLocationBridge.kt）一一对应，
/// 原生侧直连 Maven 的 com.amap.api:location（6.5.1）。
///
/// 选这条自桥路线而非 vendoring 官方 amap_flutter_location：
/// 所需面只有「隐私 + setApiKey + 单次/持续定位 + 停止」五件事，
/// 自桥代码量与攻击面都小得多，也不必再背 amap_flutter_base 的
/// 兼容补丁；代价是桥的 Kotlin 本机无 Android SDK 不能编译，
/// 首编译在出包轮次的 CI（见提交说明的未验证项）。
class ChannelAmapLocationBackend implements AmapLocationBackend {
  ChannelAmapLocationBackend({
    MethodChannel methodChannel = const MethodChannel(
      'com.shitu.app/amap_location',
    ),
    EventChannel eventChannel = const EventChannel(
      'com.shitu.app/amap_location_stream',
    ),
  }) : _method = methodChannel,
       _events = eventChannel;

  final MethodChannel _method;
  final EventChannel _events;

  bool _initialized = false;
  String _initializedKey = '';

  @override
  Future<void> init({required String apiKey}) async {
    if (_initialized && _initializedKey == apiKey) return;
    try {
      // 原生侧顺序（桥内保证）：updatePrivacyShow/Agree → 构造 client
      // → setApiKey。Dart 侧只在设置已同意隐私时才会走到这里。
      await _method.invokeMethod<bool>('init', {'apiKey': apiKey});
    } on PlatformException catch (e) {
      throw AmapLocationException(-1, e.message ?? '高德定位初始化失败');
    }
    _initialized = true;
    _initializedKey = apiKey;
  }

  @override
  Future<AmapRawFix> fetchOnce() async {
    try {
      final raw = await _method.invokeMapMethod<Object?, Object?>('fetchOnce');
      if (raw == null) {
        throw const AmapLocationException(-1, '原生未返回定位结果');
      }
      return parseAmapFix(raw);
    } on PlatformException catch (e) {
      throw AmapLocationException(-1, e.message ?? '高德定位失败');
    }
  }

  @override
  Stream<AmapRawFix> watch() {
    return _events.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return parseAmapFix(event.cast<Object?, Object?>());
      }
      throw const AmapLocationException(-1, '原生定位事件格式异常');
    });
  }

  @override
  Future<void> stop() async {
    try {
      await _method.invokeMethod<bool>('stopWatch');
    } on PlatformException {
      // 停止失败无实际影响（订阅已取消），静默。
    }
  }
}
