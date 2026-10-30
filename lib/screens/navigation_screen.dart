import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/located_fix.dart';
import '../models/map_provider.dart';
import '../models/poi.dart';
import '../models/route_plan.dart';
import '../services/location_service.dart';
import '../services/map_data_services.dart';
import '../services/navigation_controller.dart';
import '../services/settings_service.dart';
import '../services/track_service.dart';
import '../services/tts_service.dart';
import '../utils/format.dart';
import '../utils/nav_geometry.dart';
import '../widgets/app_map.dart';

/// 导航页：深色沉浸式。接 [NavigationController] 的真实状态：
/// 顶部指引横幅（下一步转向 + 距离 + 文案）、速度气泡（GPS 实测速度，
/// 不显示假限速）、偏航重规划条、底部 ETA 条、到达/结束行程小结。
///
/// 地图侧（本批）：跟随相机默认锁定当前位置；朝向默认「方向」模式
/// （车头朝上，地图按 [HeadingTracker] 平滑后的行进方向旋转），
/// 可切「北朝上」；路线只高亮当前路段剩余部分，全程剩余以极淡
/// 轮廓呈现；用户手动拖图按 [FollowLock] 规则解除跟随，点跟随/
/// 朝向按钮重新锁定。旋转只活在本页的地图实例里，退出导航后
/// 其它页面仍是北朝上。
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({
    super.key,
    required this.option,
    required this.originName,
    required this.destinationName,
    required this.destination,
    required this.mode,
    required this.provider,
    required this.settings,
    required this.services,
    required this.tracks,
    this.simulated = false,
  });

  final RouteOption option;
  final String originName;
  final String destinationName;

  /// 终点 Poi（偏航重规划的目标）。
  final Poi destination;
  final TransportMode mode;
  final MapProvider provider;
  final SettingsService settings;
  final MapDataServices services;
  final TrackService tracks;
  final bool simulated;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  late final LocationService _locationService;
  late final TtsService _tts;
  late final NavigationController _nav;
  StreamSubscription<LocatedFix>? _fixSub;
  Timer? _simTimer;
  double _simAlong = 0;
  bool _muted = false;
  bool _summaryShown = false;
  bool _ttsErrorShown = false;

  // 偏航重规划
  bool _rerouting = false;
  RouteOption? _rerouteCandidate;

  // 跟随相机与朝向（方向导航）
  final _mapHandle = MapHandle();
  final _followLock = FollowLock()..lock();
  final _headingTracker = HeadingTracker();

  /// 朝向模式：true = 方向朝上（车头朝上，默认）；false = 北朝上。
  bool _headingUp = true;

  /// 路线方向兜底用的累计距离缓存（按当前方案对象缓存，
  /// 换路线（重规划）时凭 identical 失效重算）。
  RouteOption? _headingOption;
  List<double>? _headingCumulative;

  String get _voiceLabel =>
      widget.settings.ttsEngine == TtsEngine.nvidia ? '语音 · 英伟达' : '语音 · 系统';

  @override
  void initState() {
    super.initState();
    _locationService = LocationService(settings: widget.settings);
    _tts = createTtsService(
      engine: widget.settings.ttsEngine,
      nvidiaKey: widget.settings.nvidiaKey,
      nvidiaVoice: widget.settings.nvidiaVoice,
    );
    _nav = NavigationController(
      initialOption: widget.option,
      originName: widget.originName,
      destinationName: widget.destinationName,
      mode: widget.mode,
      onAnnounce: (text) {
        if (_muted) return;
        // 播报失败（如无可用引擎）只提示一次，不再静默无声。
        _tts.speak(text).catchError((Object e) {
          if (e is TtsUnavailableException && mounted && !_ttsErrorShown) {
            _ttsErrorShown = true;
            _snack('语音播报不可用：${e.reason}');
          }
        });
      },
    );
    _nav.addListener(_onNavChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  Future<void> _begin() async {
    // 英伟达引擎 + 预合成开：先探活预合成，不可用则全程系统语音（状态可查）。
    final tts = _tts;
    if (tts is NvidiaTtsService && widget.settings.ttsPresynthesize) {
      await tts.presynthesize(widget.option.steps);
    }
    if (!mounted) return;
    _nav.start();
    if (widget.simulated) {
      _startSimulation();
      return;
    }
    try {
      await _locationService.ensureReady();
    } on LocationException catch (e) {
      if (mounted) _snack(e.message);
      return;
    }
    if (!mounted) return;
    _fixSub = _locationService.followFixStream().listen(
      _nav.updatePosition,
      onError: (Object e) {
        if (mounted && e is LocationException) _snack(e.message);
      },
    );
  }

  /// 模拟导航：沿折线以方案平均速度的 6 倍匀速推进，喂给同一个状态机。
  void _startSimulation() {
    final points = widget.option.points;
    if (points.length < 2) return;
    final cumulative = cumulativeDistances(points);
    final avgSpeed = widget.option.durationSeconds > 0
        ? widget.option.distanceMeters / widget.option.durationSeconds
        : 8.33;
    _simTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      _simAlong += avgSpeed * 6 * 0.4;
      final point = pointAtDistance(points, cumulative, _simAlong);
      _nav.updatePosition(
        LocatedFix(point: point, at: DateTime.now(), speedMps: avgSpeed),
      );
      if (_simAlong >= cumulative.last) _simTimer?.cancel();
    });
  }

  void _onNavChanged() {
    if (!mounted) return;
    setState(() {});
    _updateFollowCamera();
    if (_nav.arrived && !_summaryShown) {
      _summaryShown = true;
      _finishFlow();
    }
    if (_nav.rerouteSuggested && _rerouteCandidate == null && !_rerouting) {
      _computeReroute();
    }
  }

  /// 跟随相机：锁定中且已有定位时，把相机贴到当前位置并按朝向
  /// 模式旋转。方向来源与限速平滑在 [HeadingTracker]（定位
  /// bearing → 位移方位 → 路线方向），这里只负责命令下发：
  /// 瓦片/原生的旋转语义翻译在 MapHandle.pointUp 的实现侧。
  void _updateFollowCamera() {
    if (!_followLock.following || _nav.arrived) return;
    final fix = _nav.lastFix;
    if (fix == null) return;
    _mapHandle.moveCamera(fix.point, zoom: 17.5);
    final heading = _headingTracker.update(
      point: fix.point,
      fixBearingDegrees: fix.bearingDegrees,
      speedMps: fix.speedMps,
      routeBearingDegrees: _routeBearingAhead(),
      now: fix.at,
    );
    _mapHandle.pointUp(_headingUp ? heading : null);
  }

  /// 路线在当前进度前方约 40 米处的方位（方向兜底来源：
  /// 无定位 bearing 且位移不足时，让地图至少沿着路线转）。
  double? _routeBearingAhead() {
    final points = _nav.option.points;
    if (points.length < 2) return null;
    if (!identical(_headingOption, _nav.option)) {
      _headingOption = _nav.option;
      _headingCumulative = cumulativeDistances(points);
    }
    final cum = _headingCumulative!;
    final from = pointAtDistance(points, cum, _nav.distanceAlongMeters);
    final to = pointAtDistance(points, cum, _nav.distanceAlongMeters + 40);
    if (from == to) return null;
    return bearingDegrees(from, to);
  }

  /// 用户手动拖/转地图：按 FollowLock 既有规则解除跟随。
  void _onUserDraggedMap() => _followLock.unlockByUserGesture();

  /// 切换朝向模式并重新锁定跟随（立即按新模式贴相机）。
  void _toggleHeadingUp() {
    setState(() => _headingUp = !_headingUp);
    _followLock.lock();
    _updateFollowCamera();
  }

  /// 重新锁定跟随（用户拖走地图后出现「跟随」按钮）。
  void _relockFollow() {
    _followLock.lock();
    _updateFollowCamera();
    setState(() {});
  }

  Future<void> _computeReroute() async {
    final current = _nav.currentPoint;
    if (current == null) return;
    _rerouting = true;
    try {
      final plan = await widget.services
          .serviceFor(widget.provider)
          .planRoute(
            origin: Poi(
              id: 'gps-reroute',
              name: '我的位置',
              address: '',
              category: '我的位置',
              location: current,
            ),
            destination: widget.destination,
            mode: widget.mode,
            provider: widget.provider,
          );
      if (!mounted) return;
      setState(() {
        _rerouteCandidate =
            plan.options.where((o) => o.recommended).firstOrNull ??
            plan.options.firstOrNull;
      });
    } catch (_) {
      // 重规划失败：当作忽略处理，进入冷却，避免反复弹。
      _nav.ignoreReroute();
      if (mounted) _snack('重新规划失败，请按原路线行驶或稍后重试');
    } finally {
      _rerouting = false;
    }
  }

  void _acceptReroute() {
    final candidate = _rerouteCandidate;
    if (candidate == null) return;
    setState(() => _rerouteCandidate = null);
    _nav.replaceRoute(candidate);
  }

  void _ignoreReroute() {
    setState(() => _rerouteCandidate = null);
    _nav.ignoreReroute();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _summaryText(NavSummary summary) {
    return '识途行程：${widget.originName} → ${widget.destinationName}\n'
        '实际里程 ${formatDistance(summary.distanceMeters)} · '
        '用时 ${formatDuration(summary.durationSeconds)}'
        '${summary.arrived ? ' · 已到达' : ''}';
  }

  Future<void> _finishFlow() async {
    _fixSub?.cancel();
    _simTimer?.cancel();
    await _tts.stop();
    final summary = _nav.finish();
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(summary.arrived ? '已到达目的地' : '行程小结'),
        content: Text(
          '目的地：${widget.destinationName}\n'
          '实际里程：${formatDistance(summary.distanceMeters)}\n'
          '实际用时：${formatDuration(summary.durationSeconds)}'
          '${widget.simulated ? '\n（本次为模拟导航）' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('保存轨迹'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('share'),
            child: const Text('分享'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('close'),
            child: const Text('完成'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'save') {
      if (summary.trackPoints.length >= 2) {
        await widget.tracks.save(_nav.buildTrack());
        if (mounted) _snack('轨迹已保存，可在「收藏 / 轨迹」里回放');
      } else {
        _snack('轨迹点太少，未保存');
      }
    } else if (action == 'share') {
      await SharePlus.instance.share(ShareParams(text: _summaryText(summary)));
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束导航？'),
        content: const Text('将停止跟随与播报，并显示本次行程小结。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续导航'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('结束'),
          ),
        ],
      ),
    );
    if (ok == true && mounted && !_summaryShown) {
      _summaryShown = true;
      _finishFlow();
    }
  }

  Future<void> _showVoiceStatus() async {
    final tts = _tts;
    if (tts is SystemTtsService) {
      final readiness = await tts.probe();
      if (!mounted) return;
      if (!readiness.available) {
        _snack('系统语音不可用：${readiness.error}');
      } else {
        _snack(readiness.warning ?? '当前播报引擎：系统语音（引擎已就绪）');
      }
      return;
    }
    if (tts is NvidiaTtsService && tts.lastFallbackReason != null) {
      _snack('英伟达播报状态：${tts.lastFallbackReason}（当前实际使用系统语音）');
    } else if (widget.settings.ttsEngine == TtsEngine.nvidia) {
      _snack('当前播报引擎：英伟达 TTS（音色 ${widget.settings.nvidiaVoice}）');
    } else {
      _snack('当前播报引擎：系统语音');
    }
  }

  IconData _turnIcon(TurnDirection? direction) {
    return switch (direction) {
      TurnDirection.left || TurnDirection.sharpLeft => Icons.turn_left,
      TurnDirection.right || TurnDirection.sharpRight => Icons.turn_right,
      TurnDirection.slightLeft => Icons.turn_slight_left,
      TurnDirection.slightRight => Icons.turn_slight_right,
      TurnDirection.uturn => Icons.u_turn_left,
      null => Icons.arrow_upward,
    };
  }

  @override
  void dispose() {
    _fixSub?.cancel();
    _simTimer?.cancel();
    _tts.stop();
    _nav.removeListener(_onNavChanged);
    _nav.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = _nav.nextManeuver;
    final distToNext = _nav.distanceToNextManeuver;
    final speed = _nav.currentSpeedKmh;
    final segment = _nav.currentSegmentPoints;
    return Scaffold(
      backgroundColor: const Color(0xFF101826),
      body: Stack(
        children: [
          Positioned.fill(
            child: AppMap(
              settings: widget.settings,
              dark: true,
              // 导航态：高亮当前路段剩余 + 极淡全程剩余轮廓；
              // 尚未拿到首个定位时退回整条路线（规划态观感）。
              selectedRoutePoints: segment.isNotEmpty
                  ? segment
                  : _nav.option.points,
              routeOutlinePoints: segment.isNotEmpty
                  ? _nav.remainingRoutePoints
                  : const [],
              handle: _mapHandle,
              myLocation: _nav.currentPoint,
              showLocationDot: _nav.currentPoint == null,
              onUserDragged: _onUserDraggedMap,
            ),
          ),
          // 顶部指引横幅
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0D5C46),
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      _nav.arrived ? Icons.flag : _turnIcon(next?.direction),
                      color: Colors.white,
                      size: 44,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _nav.arrived
                                ? '已到达'
                                : distToNext != null
                                ? formatDistance(distToNext)
                                : formatDistance(_nav.remainingMeters),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _nav.arrived
                                ? '已到达「${widget.destinationName}」附近'
                                : next?.instruction ?? '继续直行',
                            style: const TextStyle(
                              color: Color(0xFFC9ECDF),
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 偏航重规划条
          if (_rerouteCandidate != null)
            Positioned(
              left: 12,
              right: 12,
              top: 128,
              child: Material(
                color: const Color(0xFFFDF3D7),
                borderRadius: BorderRadius.circular(13),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '已偏离原路线，新路线 ${formatDuration(_rerouteCandidate!.durationSeconds)} · '
                          '${formatDistance(_rerouteCandidate!.distanceMeters)}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF7A5B00),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _acceptReroute,
                        child: const Text('接受'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: '忽略（60 秒内不再提示）',
                        onPressed: _ignoreReroute,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_rerouting)
            Positioned(
              left: 12,
              right: 12,
              top: 128,
              child: Material(
                color: const Color(0xFFFDF3D7),
                borderRadius: BorderRadius.circular(13),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    '已偏离路线，正在重新规划…',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF7A5B00)),
                  ),
                ),
              ),
            ),
          // 速度气泡（GPS 实测；无速度时显示 --，不显示假限速）
          Positioned(
            left: 14,
            top: 250,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: const Color(0xFF3A4A61), width: 3),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    speed == null ? '--' : '${speed.round()}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF17233B),
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'km/h',
                    style: TextStyle(fontSize: 9.5, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          // 朝向切换（方向朝上/北朝上）与跟随重锁：右侧与速度气泡同高。
          Positioned(
            right: 14,
            top: 250,
            child: Column(
              children: [
                _roundMapButton(
                  icon: _headingUp ? Icons.navigation : Icons.explore,
                  label: _headingUp ? '方向' : '北',
                  onTap: _toggleHeadingUp,
                ),
                if (!_followLock.following) ...[
                  const SizedBox(height: 10),
                  _roundMapButton(
                    icon: Icons.my_location,
                    label: '跟随',
                    onTap: _relockFollow,
                  ),
                ],
              ],
            ),
          ),
          // 底部信息条
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: const Color(0xFF101826),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '剩余 ${formatDuration(_nav.remainingSeconds)} · '
                      '${formatDistance(_nav.remainingMeters)} · '
                      '预计 ${formatClock(_nav.eta)} 到达',
                      style: const TextStyle(
                        color: Color(0xFFDBE6F2),
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _navButton(_voiceLabel, _showVoiceStatus),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _navButton(
                            _muted ? '播报已关' : '播报开',
                            () => setState(() => _muted = !_muted),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _navButton(
                            '结束导航',
                            _confirmExit,
                            background: const Color(0xFF5C2320),
                            foreground: const Color(0xFFFFB4AB),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 地图上的圆形小按钮（朝向切换 / 跟随重锁）。
  Widget _roundMapButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: const Color(0xFF17233B)),
              Text(
                label,
                style: const TextStyle(fontSize: 9, color: Color(0xFF17233B)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navButton(
    String label,
    VoidCallback onTap, {
    Color background = const Color(0xFF1F2C3F),
    Color foreground = const Color(0xFFDBE6F2),
  }) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        padding: const EdgeInsets.symmetric(vertical: 11),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 12.5)),
    );
  }
}
