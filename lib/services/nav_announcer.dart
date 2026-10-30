import '../models/map_provider.dart';

/// 机动点播报阶段（按紧迫度递进，每段只播一次）。
enum AnnouncementStage {
  /// 预告（驾车 300 米 / 步行骑行 60 米）。
  preview,

  /// 准备（驾车 100 米 / 步行骑行 25 米）。
  prepare,

  /// 执行（驾车 30 米 / 步行骑行 10 米）。
  execute,
}

/// 一组播报距离阈值（米）：距机动点多远时进入对应阶段。
class AnnouncementThresholds {
  const AnnouncementThresholds({
    required this.previewMeters,
    required this.prepareMeters,
    required this.executeMeters,
  });

  final double previewMeters;
  final double prepareMeters;
  final double executeMeters;

  double metersFor(AnnouncementStage stage) => switch (stage) {
        AnnouncementStage.preview => previewMeters,
        AnnouncementStage.prepare => prepareMeters,
        AnnouncementStage.execute => executeMeters,
      };
}

/// 按出行方式取播报阈值（纯函数，供单测）：驾车距离长、速度快，
/// 提前量大；步行/骑行速度慢，提前量小；公交导航本质是驾车尺度，
/// 与驾车同组。
AnnouncementThresholds announcementThresholdsFor(TransportMode mode) =>
    switch (mode) {
      TransportMode.driving ||
      TransportMode.transit =>
        const AnnouncementThresholds(
          previewMeters: 300,
          prepareMeters: 100,
          executeMeters: 30,
        ),
      TransportMode.walking ||
      TransportMode.cycling =>
        const AnnouncementThresholds(
          previewMeters: 60,
          prepareMeters: 25,
          executeMeters: 10,
        ),
    };

/// 机动点播报门控状态机（纯逻辑，供单测）。
///
/// 规则：
/// - 只对「当前下一个」机动点播报。调用方（NavigationController）
///   只喂当前机动点的下标与剩余距离；下标变化意味着上一个机动点
///   已被越过，新机动点的阶段状态才从零开始——**未越过前一个，
///   绝不播下一个**（旧版越过即抢播「下一步」正是用户反馈
///   「还没到路口就播、太早」的根源，现已移除）。
/// - 每个机动点按 预告 → 准备 → 执行 三段递进，每段只播一次。
/// - 跨级到达（一帧从阈值外跳进更紧的阶段，如 400 米直接到
///   20 米）只播最紧迫的一段，更早的阶段静默标记为已播，
///   不事后回补过时文案。
/// - [reset] 后全部状态清零（偏航重规划换路线时调用）。
class ManeuverAnnouncer {
  ManeuverAnnouncer(this.thresholds);

  final AnnouncementThresholds thresholds;

  int _maneuverIndex = -1;
  final Set<AnnouncementStage> _fired = {};

  /// 当前门控中的机动点下标（供单测观察）。
  int get maneuverIndex => _maneuverIndex;

  void reset() {
    _maneuverIndex = -1;
    _fired.clear();
  }

  /// 距离对应的最紧迫阶段；还没进预告圈返回 null。
  AnnouncementStage? stageFor(double distanceToManeuverMeters) {
    if (distanceToManeuverMeters <= thresholds.executeMeters) {
      return AnnouncementStage.execute;
    }
    if (distanceToManeuverMeters <= thresholds.prepareMeters) {
      return AnnouncementStage.prepare;
    }
    if (distanceToManeuverMeters <= thresholds.previewMeters) {
      return AnnouncementStage.preview;
    }
    return null;
  }

  /// 喂入当前机动点状态，返回本帧应播报的文案（不播时为 null）。
  /// 文案模板与旧版一致：「前方 X 米，<机动文案>」，
  /// X 取命中的阶段阈值，本次只改触发时机、不改文案。
  String? advance({
    required int maneuverIndex,
    required double distanceToManeuverMeters,
    required String instruction,
  }) {
    if (maneuverIndex != _maneuverIndex) {
      _maneuverIndex = maneuverIndex;
      _fired.clear();
    }
    final stage = stageFor(distanceToManeuverMeters);
    if (stage == null) return null;
    // 跨级到达时静默消费更早阶段。
    for (final s in AnnouncementStage.values) {
      if (s.index < stage.index) _fired.add(s);
    }
    if (!_fired.add(stage)) return null;
    return '前方 ${thresholds.metersFor(stage).round()} 米，$instruction';
  }
}
