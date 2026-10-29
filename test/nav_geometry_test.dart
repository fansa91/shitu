import 'package:flutter_test/flutter_test.dart';

import 'package:shitu/models/geo_point.dart';
import 'package:shitu/utils/nav_geometry.dart';

// 深圳附近坐标：A 向东到 B（约 1027 米），再向北到 C（约 1110 米），B 处左转。
const a = GeoPoint(latitude: 22.5400, longitude: 114.0500);
const b = GeoPoint(latitude: 22.5400, longitude: 114.0600);
const c = GeoPoint(latitude: 22.5500, longitude: 114.0600);
const line = [a, b, c];

void main() {
  group('haversineMeters', () {
    test('同点为 0，向东 0.01 经度约 1027 米', () {
      expect(haversineMeters(a, a), 0);
      expect(haversineMeters(a, b), closeTo(1027, 30));
    });
  });

  group('projectOntoPolyline', () {
    test('线段中点正上方 111 米处：投影落回中点、离线距离约 111', () {
      final mid = GeoPoint(latitude: 22.5410, longitude: 114.0550);
      final p = projectOntoPolyline(mid, line);
      expect(p.distanceToLineMeters, closeTo(111, 8));
      expect(p.distanceAlongMeters,
          closeTo(haversineMeters(a, b) / 2, 25));
      expect(p.segmentIndex, 0);
    });

    test('终点之后：沿线距离封顶为总长', () {
      final beyond = GeoPoint(latitude: 22.5600, longitude: 114.0600);
      final p = projectOntoPolyline(beyond, line);
      expect(p.distanceAlongMeters, closeTo(polylineLength(line), 30));
      expect(p.projectedPoint, c);
    });
  });

  group('pointAtDistance', () {
    test('取中点与终点', () {
      final cum = cumulativeDistances(line);
      final total = cum.last;
      final mid = pointAtDistance(line, cum, total / 2);
      // 中点落在折线上：把它投影回去，沿线距离应等于 total/2。
      expect(projectOntoPolyline(mid, line).distanceAlongMeters,
          closeTo(total / 2, 5));
      expect(pointAtDistance(line, cum, total + 500), c);
      expect(pointAtDistance(line, cum, -5), a);
    });
  });

  group('buildManeuvers', () {
    test('东→北为左转，文案取 steps 第 2 条', () {
      final cum = cumulativeDistances(line);
      final maneuvers = buildManeuvers(line, cum, const [
        '从起点出发',
        '左转进入中山路',
        '到达目的地',
      ]);
      expect(maneuvers, hasLength(1));
      expect(maneuvers.single.direction, TurnDirection.left);
      expect(maneuvers.single.instruction, '左转进入中山路');
      expect(maneuvers.single.distanceAlongMeters,
          closeTo(haversineMeters(a, b), 1));
    });

    test('无文案时按方向生成', () {
      final cum = cumulativeDistances(line);
      final maneuvers = buildManeuvers(line, cum, const []);
      expect(maneuvers.single.instruction, '左转');
    });

    test('直行折线无转向点', () {
      const straight = [
        GeoPoint(latitude: 22.5400, longitude: 114.0500),
        GeoPoint(latitude: 22.5400, longitude: 114.0550),
        GeoPoint(latitude: 22.5400, longitude: 114.0600),
      ];
      final cum = cumulativeDistances(straight);
      expect(buildManeuvers(straight, cum, const []), isEmpty);
    });
  });
}
