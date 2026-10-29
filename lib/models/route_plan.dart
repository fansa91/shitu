import 'geo_point.dart';
import 'map_provider.dart';

/// 一条候选路线方案。
class RouteOption {
  const RouteOption({
    required this.durationSeconds,
    required this.distanceMeters,
    required this.tollYuan,
    required this.trafficLights,
    required this.strategyTags,
    required this.provider,
    this.recommended = false,
    this.points = const [],
    this.steps = const [],
  });

  /// 路线折线点（GCJ-02），地图上绘制用；示例数据可为空。
  final List<GeoPoint> points;

  /// 分步导航文案（如「沿深南大道向东行驶 1.2 公里」），离线路线展示用；
  /// 服务商未返回时为空。
  final List<String> steps;

  /// 预计时长（秒）。
  final int durationSeconds;

  /// 路线长度（米）。
  final double distanceMeters;

  /// 过路费（元），0 表示无收费。
  final int tollYuan;

  /// 途经红绿灯数量。
  final int trafficLights;

  /// 策略标签，如「躲避拥堵」「少收费」。
  final List<String> strategyTags;

  /// 给出该方案的服务商（多方案可跨服务商对比）。
  final MapProvider provider;

  final bool recommended;
}

/// 一次算路的完整结果：起点、终点、出行方式与多条方案。
class RoutePlan {
  const RoutePlan({
    required this.originName,
    required this.destinationName,
    required this.mode,
    required this.options,
  });

  final String originName;
  final String destinationName;
  final TransportMode mode;
  final List<RouteOption> options;
}
