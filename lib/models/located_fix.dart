import 'geo_point.dart';

/// 一次定位采样：位置（GCJ-02）+ GPS 速度 + 采样时刻。
/// 导航跟随与轨迹记录的统一输入。
class LocatedFix {
  const LocatedFix({
    required this.point,
    required this.at,
    this.speedMps,
  });

  /// 位置（GCJ-02）。
  final GeoPoint point;

  /// 采样时刻。
  final DateTime at;

  /// GPS 速度（米/秒）；设备未提供时为 null（负值按未提供处理）。
  final double? speedMps;

  /// 速度（km/h），无速度时为 null。
  double? get speedKmh =>
      speedMps == null ? null : speedMps! * 3.6;
}
