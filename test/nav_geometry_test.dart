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

  group('bearingDegrees / 角度步进', () {
    test('向东约 90、向北约 0', () {
      expect(bearingDegrees(a, b), closeTo(90, 1));
      expect(bearingDegrees(b, c), closeTo(0, 1));
    });

    test('正规化与最短弧角差', () {
      expect(normalizeBearingDegrees(-90), 270);
      expect(normalizeBearingDegrees(370), 10);
      expect(shortestArcDeltaDegrees(350, 10), closeTo(20, 1e-9));
      expect(shortestArcDeltaDegrees(10, 350), closeTo(-20, 1e-9));
    });

    test('步进限速：单步不超过上限；限内直达目标', () {
      expect(stepBearingDegrees(350, 10, 5), closeTo(355, 1e-9));
      expect(stepBearingDegrees(10, 350, 5), closeTo(5, 1e-9));
      expect(stepBearingDegrees(0, 30, 45), closeTo(30, 1e-9));
    });
  });

  group('subPolyline 当前路段裁剪', () {
    test('中段裁剪：首尾为插值点、中间顶点保留', () {
      final cum = cumulativeDistances(line);
      final abLen = haversineMeters(a, b);
      final seg = subPolyline(line, cum, abLen / 2, abLen + 100);
      expect(seg.length, 3); // 插值起点 + b + 插值终点
      expect(seg[1], b);
      expect(
        projectOntoPolyline(seg.first, line).distanceAlongMeters,
        closeTo(abLen / 2, 5),
      );
      expect(
        projectOntoPolyline(seg.last, line).distanceAlongMeters,
        closeTo(abLen + 100, 5),
      );
    });

    test('全程裁剪与原折线一致；越界距离自动夹紧', () {
      final cum = cumulativeDistances(line);
      expect(subPolyline(line, cum, 0, cum.last), line);
      expect(subPolyline(line, cum, -50, cum.last + 999), line);
    });
  });

  group('HeadingTracker', () {
    final t0 = DateTime(2026, 10, 30, 12);
    const east10m = GeoPoint(latitude: 22.5400, longitude: 114.0501);
    const north11m = GeoPoint(latitude: 22.5401, longitude: 114.0500);

    test('定位 bearing 优先：速度够快时首帧即采用', () {
      final tracker = HeadingTracker();
      final h = tracker.update(
        point: a,
        fixBearingDegrees: 90,
        speedMps: 5,
        now: t0,
      );
      expect(h, closeTo(90, 1e-9));
    });

    test('静止时 bearing 不可信：无其它来源返回 null', () {
      final tracker = HeadingTracker();
      final h = tracker.update(
        point: a,
        fixBearingDegrees: 90,
        speedMps: 0,
        now: t0,
      );
      expect(h, isNull);
    });

    test('位移方位：与锚点拉开 ≥4 米后由两点算出', () {
      final tracker = HeadingTracker();
      expect(tracker.update(point: a, now: t0), isNull);
      final h = tracker.update(
        point: east10m,
        now: t0.add(const Duration(seconds: 1)),
      );
      expect(h, closeTo(90, 1));
    });

    test('路线方向兜底：无 bearing 无位移时用路线方位', () {
      final tracker = HeadingTracker();
      final h = tracker.update(point: a, routeBearingDegrees: 180, now: t0);
      expect(h, closeTo(180, 1e-9));
    });

    test('限速平滑：目标突变时按 120°/秒追赶，不甩图', () {
      final tracker = HeadingTracker();
      tracker.update(point: a, now: t0);
      // 先向北走出一段，朝向定为 0。
      final north = tracker.update(
        point: north11m,
        now: t0.add(const Duration(seconds: 1)),
      );
      expect(north, closeTo(0, 1));
      // 0.1 秒后突然出现向东位移：目标 90，本帧最多转 12°。
      const eastOfNorth = GeoPoint(latitude: 22.5401, longitude: 114.0501);
      final h = tracker.update(
        point: eastOfNorth,
        now: t0.add(const Duration(milliseconds: 1100)),
      );
      expect(h, closeTo(12, 1));
    });
  });
}
