import 'dart:math' as math;

import '../models/geo_point.dart';

// 导航几何工具（纯函数，供单测）：球面距离、点到折线的投影、
// 沿折线取点、按方向变化提取转向点（机动点）。
// 坐标为 GCJ-02 经纬度，小范围内用局部平面近似（米）。

const double _earthRadius = 6371000.0;
const double _degToRad = math.pi / 180.0;

/// 两点间球面距离（米，haversine）。
double haversineMeters(GeoPoint a, GeoPoint b) {
  final dLat = (b.latitude - a.latitude) * _degToRad;
  final dLng = (b.longitude - a.longitude) * _degToRad;
  final lat1 = a.latitude * _degToRad;
  final lat2 = b.latitude * _degToRad;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * _earthRadius * math.asin(math.min(1, math.sqrt(h)));
}

/// 折线各段累计长度：返回长度为 points.length 的列表，
/// 第 i 项为从起点沿折线到第 i 个顶点的距离（米）。
List<double> cumulativeDistances(List<GeoPoint> points) {
  final result = List<double>.filled(points.length, 0);
  for (var i = 1; i < points.length; i++) {
    result[i] = result[i - 1] + haversineMeters(points[i - 1], points[i]);
  }
  return result;
}

/// 折线总长（米）。
double polylineLength(List<GeoPoint> points) =>
    points.length < 2 ? 0 : cumulativeDistances(points).last;

/// 点在折线上的投影结果。
class PolylineProjection {
  const PolylineProjection({
    required this.distanceAlongMeters,
    required this.distanceToLineMeters,
    required this.segmentIndex,
    required this.projectedPoint,
  });

  /// 投影点距折线起点的沿线距离（米）。
  final double distanceAlongMeters;

  /// 点到折线的最短距离（米）。
  final double distanceToLineMeters;

  /// 投影所在线段的起点顶点下标。
  final int segmentIndex;

  /// 投影点坐标。
  final GeoPoint projectedPoint;
}

/// 把 [point] 投影到折线上（局部平面近似）。折线不足 2 点时退化为到单点距离。
PolylineProjection projectOntoPolyline(GeoPoint point, List<GeoPoint> line) {
  if (line.isEmpty) {
    return PolylineProjection(
      distanceAlongMeters: 0,
      distanceToLineMeters: 0,
      segmentIndex: 0,
      projectedPoint: point,
    );
  }
  if (line.length == 1) {
    return PolylineProjection(
      distanceAlongMeters: 0,
      distanceToLineMeters: haversineMeters(point, line.first),
      segmentIndex: 0,
      projectedPoint: line.first,
    );
  }
  // 以 point 为原点的局部平面（x 东、y 北，单位米）。
  final cosLat = math.cos(point.latitude * _degToRad);
  (double, double) toLocal(GeoPoint p) => (
        (p.longitude - point.longitude) * _degToRad * _earthRadius * cosLat,
        (p.latitude - point.latitude) * _degToRad * _earthRadius,
      );
  final cumulative = cumulativeDistances(line);
  var bestDist = double.infinity;
  var bestAlong = 0.0;
  var bestSegment = 0;
  GeoPoint bestPoint = line.first;
  for (var i = 0; i + 1 < line.length; i++) {
    final a = toLocal(line[i]);
    final b = toLocal(line[i + 1]);
    final dx = b.$1 - a.$1;
    final dy = b.$2 - a.$2;
    final lenSq = dx * dx + dy * dy;
    var t = lenSq == 0 ? 0.0 : (-a.$1 * dx - a.$2 * dy) / lenSq;
    t = t.clamp(0.0, 1.0);
    final px = a.$1 + dx * t;
    final py = a.$2 + dy * t;
    final dist = math.sqrt(px * px + py * py);
    if (dist < bestDist) {
      bestDist = dist;
      bestSegment = i;
      bestAlong = cumulative[i] +
          haversineMeters(line[i], line[i + 1]) * t;
      bestPoint = GeoPoint(
        latitude: line[i].latitude +
            (line[i + 1].latitude - line[i].latitude) * t,
        longitude: line[i].longitude +
            (line[i + 1].longitude - line[i].longitude) * t,
      );
    }
  }
  return PolylineProjection(
    distanceAlongMeters: bestAlong,
    distanceToLineMeters: bestDist,
    segmentIndex: bestSegment,
    projectedPoint: bestPoint,
  );
}

/// 沿折线距起点 [distanceAlong] 米处的点（超出终点返回终点）。
GeoPoint pointAtDistance(
  List<GeoPoint> line,
  List<double> cumulative,
  double distanceAlong,
) {
  if (line.isEmpty) return const GeoPoint(latitude: 0, longitude: 0);
  if (distanceAlong <= 0 || line.length == 1) return line.first;
  if (distanceAlong >= cumulative.last) return line.last;
  var i = 0;
  while (i + 1 < cumulative.length && cumulative[i + 1] < distanceAlong) {
    i++;
  }
  final segLen = cumulative[i + 1] - cumulative[i];
  final t = segLen == 0 ? 0 : (distanceAlong - cumulative[i]) / segLen;
  return GeoPoint(
    latitude: line[i].latitude + (line[i + 1].latitude - line[i].latitude) * t,
    longitude:
        line[i].longitude + (line[i + 1].longitude - line[i].longitude) * t,
  );
}

/// 转向方向（由折线方向变化判定）。
enum TurnDirection { slightLeft, left, sharpLeft, uturn, slightRight, right, sharpRight }

extension TurnDirectionX on TurnDirection {
  String get label => switch (this) {
        TurnDirection.slightLeft => '靠左行驶',
        TurnDirection.left => '左转',
        TurnDirection.sharpLeft => '向左急转',
        TurnDirection.uturn => '掉头',
        TurnDirection.slightRight => '靠右行驶',
        TurnDirection.right => '右转',
        TurnDirection.sharpRight => '向右急转',
      };

  bool get isLeft =>
      this == TurnDirection.slightLeft ||
      this == TurnDirection.left ||
      this == TurnDirection.sharpLeft;
}

/// 一个转向机动点：距起点的沿线距离 + 方向 + 播报文案。
class Maneuver {
  const Maneuver({
    required this.distanceAlongMeters,
    required this.direction,
    required this.instruction,
    required this.vertexIndex,
  });

  final double distanceAlongMeters;
  final TurnDirection direction;

  /// 播报/横幅文案：优先取服务商分步文案，没有时按方向生成。
  final String instruction;

  /// 转向点在折线顶点中的下标。
  final int vertexIndex;
}

double _bearing(GeoPoint from, GeoPoint to) {
  final cosLat = math.cos(from.latitude * _degToRad);
  final dx = (to.longitude - from.longitude) * cosLat;
  final dy = to.latitude - from.latitude;
  return math.atan2(dx, dy); // 0 = 正北，顺时针为正
}

TurnDirection _directionFor(double deltaRad) {
  final deg = deltaRad / _degToRad;
  final abs = deg.abs();
  if (abs >= 150) return TurnDirection.uturn;
  if (deg > 0) {
    if (abs >= 100) return TurnDirection.sharpRight;
    if (abs >= 30) return TurnDirection.right;
    return TurnDirection.slightRight;
  }
  if (abs >= 100) return TurnDirection.sharpLeft;
  if (abs >= 30) return TurnDirection.left;
  return TurnDirection.slightLeft;
}

/// 从折线提取转向机动点：相邻线段方向变化 ≥ [minTurnDegrees] 度视为转向；
/// 相距不足 [minSeparationMeters] 的多个转向只保留转角最大的一个。
/// [steps] 为服务商分步文案：第 0 条通常是出发文案，转向文案从第 1 条起顺延；
/// 文案充足时按顺序取用，不足时按方向生成「前方左转」类文案。
List<Maneuver> buildManeuvers(
  List<GeoPoint> points,
  List<double> cumulative,
  List<String> steps, {
  double minTurnDegrees = 28,
  double minSeparationMeters = 45,
}) {
  if (points.length < 3) return const [];
  final raw = <Maneuver>[];
  final rawDelta = <double>[];
  for (var i = 1; i + 1 < points.length; i++) {
    final b1 = _bearing(points[i - 1], points[i]);
    final b2 = _bearing(points[i], points[i + 1]);
    var delta = b2 - b1;
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta < -math.pi) {
      delta += 2 * math.pi;
    }
    if (delta.abs() / _degToRad < minTurnDegrees) continue;
    raw.add(Maneuver(
      distanceAlongMeters: cumulative[i],
      direction: _directionFor(delta),
      instruction: '',
      vertexIndex: i,
    ));
    rawDelta.add(delta.abs());
  }
  // 合并过近的转向点，保留转角最大者。
  final merged = <Maneuver>[];
  final mergedDelta = <double>[];
  for (var k = 0; k < raw.length; k++) {
    if (merged.isNotEmpty &&
        raw[k].distanceAlongMeters - merged.last.distanceAlongMeters <
            minSeparationMeters) {
      if (rawDelta[k] > mergedDelta.last) {
        merged[merged.length - 1] = raw[k];
        mergedDelta[mergedDelta.length - 1] = rawDelta[k];
      }
      continue;
    }
    merged.add(raw[k]);
    mergedDelta.add(rawDelta[k]);
  }
  // 分配文案：steps[0] 为出发文案，转向从 steps[1] 起顺延；
  // 文案不够时按方向生成。
  return [
    for (var k = 0; k < merged.length; k++)
      Maneuver(
        distanceAlongMeters: merged[k].distanceAlongMeters,
        direction: merged[k].direction,
        vertexIndex: merged[k].vertexIndex,
        instruction: (k + 1 < steps.length && steps[k + 1].trim().isNotEmpty)
            ? steps[k + 1].trim()
            : merged[k].direction.label,
      ),
  ];
}
