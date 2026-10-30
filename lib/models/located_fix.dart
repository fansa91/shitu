import 'geo_point.dart';

/// 定位结果的来源（坐标纪律按来源区分）：
/// - [amap]：高德定位 SDK，原生返回即 GCJ-02，**禁止再做坐标转换**；
/// - [system]：系统定位（geolocator），原始 WGS-84，进 App 前转 GCJ-02。
enum LocationSource {
  amap,
  system;

  String get label => switch (this) {
    LocationSource.amap => '高德定位',
    LocationSource.system => '系统定位',
  };
}

/// 定位源偏好（三档，用户在设置页选）：
/// - [auto]：有 Key 且条件齐时先试高德，失败/首定超时自动回落系统；
/// - [amap]：强制高德，不可用时如实报错（不静默回落）；
/// - [system]：强制系统定位。
/// 高德定位仅 Android 可用（桥只做 Android），其它平台恒走系统。
enum LocationSourceMode {
  auto,
  amap,
  system;

  String get label => switch (this) {
    LocationSourceMode.auto => '自动',
    LocationSourceMode.amap => '高德',
    LocationSourceMode.system => '系统',
  };
}

/// 一次定位采样：位置（GCJ-02）+ GPS 速度 + 采样时刻。
/// 导航跟随与轨迹记录的统一输入。
class LocatedFix {
  const LocatedFix({
    required this.point,
    required this.at,
    this.speedMps,
    this.source = LocationSource.system,
  });

  /// 位置（GCJ-02）。
  final GeoPoint point;

  /// 结果来源：决定 [point] 的坐标处理路径（见 [LocationSource]）。
  final LocationSource source;

  /// 采样时刻。
  final DateTime at;

  /// GPS 速度（米/秒）；设备未提供时为 null（负值按未提供处理）。
  final double? speedMps;

  /// 速度（km/h），无速度时为 null。
  double? get speedKmh =>
      speedMps == null ? null : speedMps! * 3.6;
}
