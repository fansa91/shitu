import 'package:flutter/foundation.dart';

import '../models/geo_point.dart';
import '../models/located_fix.dart';
import '../models/map_provider.dart';
import '../models/nav_track.dart';
import '../models/route_plan.dart';
import '../utils/nav_geometry.dart';
import 'nav_announcer.dart';

/// 导航结束时的小结数据（里程/用时取自实走轨迹）。
class NavSummary {
  const NavSummary({
    required this.trackPoints,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.arrived,
  });

  final List<GeoPoint> trackPoints;
  final double distanceMeters;
  final int durationSeconds;
  final bool arrived;
}

/// 轻量跟随导航状态机（纯逻辑 + ChangeNotifier，UI 与播报都挂在它上面）。
///
/// 输入：选中的 [RouteOption]（折线 + 分步文案）与 [LocatedFix] 位置流。
/// 职责：步骤推进（按折线几何提取的转向点）、机动点分段门控播报
/// （见 [ManeuverAnnouncer]：越过上一机动点才解锁下一个，按距离
/// 三段递进、每段一次）、剩余距离与 ETA、偏航判定
/// （离线 >50m 连续两次采样 → 建议重规划；忽略后 60 秒冷却）、轨迹记录。
class NavigationController extends ChangeNotifier {
  NavigationController({
    required RouteOption initialOption,
    required this.originName,
    required this.destinationName,
    this.mode = TransportMode.driving,
    void Function(String text)? onAnnounce,
    DateTime Function()? clock,
  })  : _option = initialOption,
        _announce = onAnnounce,
        _clock = clock ?? DateTime.now,
        _announcer = ManeuverAnnouncer(announcementThresholdsFor(mode)) {
    _resetRoute();
  }

  final String originName;
  final String destinationName;

  /// 出行方式：决定机动点播报阈值（驾车 300/100/30 米，
  /// 步行骑行 60/25/10 米）。
  final TransportMode mode;

  final ManeuverAnnouncer _announcer;
  final void Function(String text)? _announce;
  final DateTime Function() _clock;

  RouteOption _option;
  RouteOption get option => _option;

  late List<double> _cumulative;
  late List<Maneuver> _maneuvers;
  late double _totalMeters;

  bool _started = false;
  bool _arrived = false;
  DateTime? _startedAt;

  LocatedFix? _lastFix;
  double _distanceAlong = 0;
  double _offLineMeters = 0;
  int _currentManeuverIndex = 0;
  final Set<String> _spoken = {};

  // 偏航判定
  int _offRouteStreak = 0;
  bool _rerouteSuggested = false;
  DateTime? _rerouteCooldownUntil;

  // 轨迹记录（移动 ≥3 米才记一点，控制体积）
  final List<GeoPoint> _trackPoints = [];
  double _trackDistanceMeters = 0;

  bool get started => _started;
  bool get arrived => _arrived;

  /// 最近一次定位采样（含 bearing/速度/精度），导航页方向
  /// 跟踪取 bearing 用；尚无采样时为 null。
  LocatedFix? get lastFix => _lastFix;
  GeoPoint? get currentPoint => _lastFix?.point;
  double? get currentSpeedKmh => _lastFix?.speedKmh;
  double get distanceAlongMeters => _distanceAlong;
  double get offLineMeters => _offLineMeters;
  double get totalMeters => _totalMeters;
  double get remainingMeters =>
      (_totalMeters - _distanceAlong).clamp(0, double.infinity).toDouble();

  /// 剩余时间：按方案自身平均速度估算（方案距离/时长），无有效值时回落 30km/h。
  int get remainingSeconds {
    final avg = _option.durationSeconds > 0 && _option.distanceMeters > 0
        ? _option.distanceMeters / _option.durationSeconds
        : 8.33;
    return (remainingMeters / avg).round();
  }

  DateTime get eta => _clock().add(Duration(seconds: remainingSeconds));

  /// 下一个未通过的转向点；全部通过后为 null（横幅改显直行/到达）。
  Maneuver? get nextManeuver =>
      _currentManeuverIndex < _maneuvers.length
          ? _maneuvers[_currentManeuverIndex]
          : null;

  double? get distanceToNextManeuver {
    final m = nextManeuver;
    if (m == null) return null;
    return (m.distanceAlongMeters - _distanceAlong)
        .clamp(0, double.infinity)
        .toDouble();
  }

  /// 当前路段的剩余折线（导航态地图的高亮层）：从当前位置在
  /// 路线上的投影点到下一个机动点（无机动点时到终点）。
  /// 已走过的部分不在其中。未开始/无位置/无折线时为空。
  List<GeoPoint> get currentSegmentPoints {
    if (!_started || _lastFix == null || _option.points.length < 2) {
      return const [];
    }
    final endAlong = nextManeuver?.distanceAlongMeters ?? _totalMeters;
    return subPolyline(
      _option.points,
      _cumulative,
      _distanceAlong,
      endAlong,
    );
  }

  /// 全程剩余折线（投影点 → 终点）：导航态作极淡色轮廓层，
  /// 让「当前段清晰、全程可感知」。条件同 [currentSegmentPoints]。
  List<GeoPoint> get remainingRoutePoints {
    if (!_started || _lastFix == null || _option.points.length < 2) {
      return const [];
    }
    return subPolyline(
      _option.points,
      _cumulative,
      _distanceAlong,
      _totalMeters,
    );
  }

  bool get rerouteSuggested => _rerouteSuggested;
  List<GeoPoint> get trackPoints => List.unmodifiable(_trackPoints);
  double get trackDistanceMeters => _trackDistanceMeters;

  int get elapsedSeconds =>
      _startedAt == null ? 0 : _clock().difference(_startedAt!).inSeconds;

  void _resetRoute() {
    final points = _option.points;
    _cumulative = cumulativeDistances(points);
    _totalMeters = points.length < 2 ? _option.distanceMeters : _cumulative.last;
    _maneuvers = buildManeuvers(points, _cumulative, _option.steps);
    _currentManeuverIndex = 0;
    _distanceAlong = 0;
    _offLineMeters = 0;
    _offRouteStreak = 0;
    _rerouteSuggested = false;
  }

  /// 开始导航：播报出发文案并开始计时/记轨迹。
  void start() {
    if (_started) return;
    _started = true;
    _startedAt = _clock();
    final first = _option.steps.isNotEmpty
        ? _option.steps.first
        : '出发，前往$destinationName';
    _speakOnce('start', '开始导航。$first');
    notifyListeners();
  }

  void _speakOnce(String key, String text) {
    if (_spoken.add(key)) _announce?.call(text);
  }

  /// 喂入一个定位采样，推进状态机。
  void updatePosition(LocatedFix fix) {
    if (!_started || _arrived) return;
    _lastFix = fix;
    _recordTrack(fix.point);
    final points = _option.points;
    if (points.length >= 2) {
      final projection = projectOntoPolyline(fix.point, points);
      // 只前进不后退（GPS 抖动不让进度倒退超过 30 米）。
      if (projection.distanceAlongMeters > _distanceAlong - 30) {
        _distanceAlong = projection.distanceAlongMeters;
      }
      _offLineMeters = projection.distanceToLineMeters;
      _updateOffRoute(fix);
      _updateManeuvers();
      _checkArrivalByProjection(fix);
    } else {
      // 没有折线（如示例数据缺失）时按到终点直线距离粗判到达。
      _checkArrivalByProximity(fix);
    }
    notifyListeners();
  }

  void _recordTrack(GeoPoint point) {
    if (_trackPoints.isEmpty) {
      _trackPoints.add(point);
      return;
    }
    final d = haversineMeters(_trackPoints.last, point);
    if (d >= 3) {
      _trackDistanceMeters += d;
      _trackPoints.add(point);
    }
  }

  void _updateManeuvers() {
    // 推进已通过的转向点（只推进状态、不出声：旧版越过即抢播
    // 「下一步：…」是用户反馈「还没到路口就播、太早」的根源）。
    while (_currentManeuverIndex < _maneuvers.length &&
        _distanceAlong > _maneuvers[_currentManeuverIndex].distanceAlongMeters + 15) {
      _currentManeuverIndex++;
    }
    final m = nextManeuver;
    if (m == null) return;
    // 门控状态机只喂「当前下一个」机动点：其下标变化即代表上一
    // 机动点已越过，新机动点这才解锁、按距离三段递进播报。
    final text = _announcer.advance(
      maneuverIndex: _currentManeuverIndex,
      distanceToManeuverMeters: (m.distanceAlongMeters - _distanceAlong)
          .clamp(0, double.infinity)
          .toDouble(),
      instruction: m.instruction,
    );
    if (text != null) _announce?.call(text);
  }

  void _updateOffRoute(LocatedFix fix) {
    if (_offLineMeters > 50) {
      _offRouteStreak++;
    } else {
      _offRouteStreak = 0;
      if (_rerouteSuggested) _rerouteSuggested = false;
    }
    if (_offRouteStreak >= 2 && !_rerouteSuggested) {
      final cooldown = _rerouteCooldownUntil;
      if (cooldown == null || fix.at.isAfter(cooldown)) {
        _rerouteSuggested = true;
      }
    }
  }

  /// 用户忽略重规划建议：关条并进入 60 秒冷却（冷却内不再弹）。
  void ignoreReroute() {
    _rerouteSuggested = false;
    _offRouteStreak = 0;
    _rerouteCooldownUntil = _clock().add(const Duration(seconds: 60));
    notifyListeners();
  }

  /// 接受重规划：用新方案替换当前路线（进度、播报、偏航状态重置；
  /// 已记录轨迹保留，继续累积）。
  void replaceRoute(RouteOption newOption) {
    _option = newOption;
    _rerouteSuggested = false;
    _rerouteCooldownUntil = null;
    _announcer.reset();
    _resetRoute();
    _speakOnce(
      'rerouted-${_clock().millisecondsSinceEpoch}',
      '已切换到新路线',
    );
    notifyListeners();
  }

  void _checkArrivalByProjection(LocatedFix fix) {
    if (remainingMeters <= 25) _arrive();
  }

  void _checkArrivalByProximity(LocatedFix fix) {
    final dest = _option.points.isEmpty ? null : _option.points.last;
    if (dest != null && haversineMeters(fix.point, dest) <= 30) _arrive();
  }

  void _arrive() {
    if (_arrived) return;
    _arrived = true;
    _speakOnce('arrive', '已到达目的地$destinationName附近，导航结束');
    notifyListeners();
  }

  /// 结束导航并生成小结（轨迹点不足 2 个时里程以轨迹累计为准，可能为 0）。
  NavSummary finish() {
    return NavSummary(
      trackPoints: List.unmodifiable(_trackPoints),
      distanceMeters: _trackDistanceMeters,
      durationSeconds: elapsedSeconds,
      arrived: _arrived,
    );
  }

  /// 组装可保存的轨迹对象（名称默认「起点 → 终点 · 月/日 时:分」）。
  NavTrack buildTrack() {
    final start = _startedAt ?? _clock();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = '$originName → $destinationName · '
        '${start.month}/${start.day} ${two(start.hour)}:${two(start.minute)}';
    return NavTrack(
      id: 'track-${start.millisecondsSinceEpoch}',
      name: name,
      originName: originName,
      destinationName: destinationName,
      points: List.of(_trackPoints),
      distanceMeters: _trackDistanceMeters,
      durationSeconds: elapsedSeconds,
      startedAtMs: start.millisecondsSinceEpoch,
    );
  }
}
