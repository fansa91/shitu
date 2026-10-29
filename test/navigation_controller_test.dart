import 'package:flutter_test/flutter_test.dart';

import 'package:shitu/models/geo_point.dart';
import 'package:shitu/models/located_fix.dart';
import 'package:shitu/models/map_provider.dart';
import 'package:shitu/models/route_plan.dart';
import 'package:shitu/services/navigation_controller.dart';
import 'package:shitu/utils/nav_geometry.dart';

const a = GeoPoint(latitude: 22.5400, longitude: 114.0500);
const b = GeoPoint(latitude: 22.5400, longitude: 114.0600);
const c = GeoPoint(latitude: 22.5500, longitude: 114.0600);
const line = [a, b, c];

RouteOption makeOption() {
  final total = polylineLength(line);
  return RouteOption(
    durationSeconds: (total / 10).round(), // 平均 10 m/s
    distanceMeters: total,
    tollYuan: 0,
    trafficLights: 0,
    strategyTags: const ['推荐路线'],
    provider: MapProvider.amap,
    recommended: true,
    points: line,
    steps: const ['从起点出发', '左转进入中山路', '到达目的地'],
  );
}

void main() {
  late List<String> spoken;
  late NavigationController nav;
  final cum = cumulativeDistances(line);
  final abLen = haversineMeters(a, b);

  LocatedFix fixAt(double along, {double latOffset = 0}) {
    final p = pointAtDistance(line, cum, along);
    return LocatedFix(
      point: GeoPoint(
        latitude: p.latitude + latOffset,
        longitude: p.longitude,
      ),
      at: DateTime.now(),
      speedMps: 10,
    );
  }

  setUp(() {
    spoken = [];
    nav = NavigationController(
      initialOption: makeOption(),
      originName: '起点',
      destinationName: '终点',
      onAnnounce: spoken.add,
    );
  });

  tearDown(() => nav.dispose());

  test('出发播报一次；300m/100m 分级播报不重复', () {
    nav.start();
    expect(spoken, hasLength(1));
    expect(spoken.single, contains('开始导航'));

    nav.updatePosition(fixAt(abLen - 350));
    expect(spoken, hasLength(1)); // 还没到 300 米

    nav.updatePosition(fixAt(abLen - 280));
    expect(spoken.last, contains('前方 300 米'));
    expect(spoken.last, contains('左转进入中山路'));

    nav.updatePosition(fixAt(abLen - 270)); // 同级不重复
    expect(spoken.where((s) => s.contains('300 米')), hasLength(1));

    nav.updatePosition(fixAt(abLen - 80));
    expect(spoken.last, contains('前方 100 米'));
  });

  test('剩余距离与 ETA 随推进减少', () {
    nav.start();
    nav.updatePosition(fixAt(500));
    expect(nav.remainingMeters, closeTo(nav.totalMeters - 500, 40));
    expect(nav.remainingSeconds, lessThan(makeOption().durationSeconds));
    expect(nav.distanceToNextManeuver, closeTo(abLen - 500, 40));
  });

  test('到达终点附近判定到达并播报', () {
    nav.start();
    nav.updatePosition(fixAt(cum.last - 10));
    expect(nav.arrived, isTrue);
    expect(spoken.any((s) => s.contains('已到达目的地')), isTrue);
  });

  test('连续两次偏离 >50 米建议重规划；忽略后冷却内不再弹', () {
    nav.start();
    final off = fixAt(400, latOffset: 0.0012); // 约偏离 133 米
    nav.updatePosition(off);
    expect(nav.rerouteSuggested, isFalse); // 第一次只计数
    nav.updatePosition(off);
    expect(nav.rerouteSuggested, isTrue);

    nav.ignoreReroute();
    expect(nav.rerouteSuggested, isFalse);
    nav.updatePosition(off);
    nav.updatePosition(off);
    expect(nav.rerouteSuggested, isFalse); // 60 秒冷却内
  });

  test('回到路线上清除偏航建议', () {
    nav.start();
    final off = fixAt(400, latOffset: 0.0012);
    nav.updatePosition(off);
    nav.updatePosition(off);
    expect(nav.rerouteSuggested, isTrue);
    nav.updatePosition(fixAt(420));
    expect(nav.rerouteSuggested, isFalse);
  });

  test('轨迹记录累计里程，可组装保存对象', () {
    nav.start();
    nav.updatePosition(fixAt(0));
    nav.updatePosition(fixAt(300));
    nav.updatePosition(fixAt(600));
    expect(nav.trackPoints.length, greaterThanOrEqualTo(3));
    expect(nav.trackDistanceMeters, closeTo(600, 60));
    final track = nav.buildTrack();
    expect(track.name, contains('起点 → 终点'));
    expect(track.points, isNotEmpty);
  });

  test('接受重规划替换路线并重置进度', () {
    nav.start();
    nav.updatePosition(fixAt(500));
    final shorter = RouteOption(
      durationSeconds: 60,
      distanceMeters: 600,
      tollYuan: 0,
      trafficLights: 0,
      strategyTags: const ['新路线'],
      provider: MapProvider.amap,
      points: const [a, b],
      steps: const ['沿当前道路行驶'],
    );
    nav.replaceRoute(shorter);
    expect(nav.option, shorter);
    expect(nav.distanceAlongMeters, 0);
    // 有折线时剩余距离以折线实长为准（a→b 约 1027 米）。
    expect(nav.remainingMeters, closeTo(haversineMeters(a, b), 30));
  });
}
