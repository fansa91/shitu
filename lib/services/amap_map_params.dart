/// 真实地图「两段式」下发参数（纯逻辑，便于单测）。
///
/// 背景（v0.2.2 真机面包屑实锤）：一加 7 Pro / Android 10 上，SDK
/// 初始化正常完成、签名/Key 已排除，进程死在 amap_map 1.0.15 的
/// TextureMapView 原生创建内部（「地图创建开始」之后、onMapCreated
/// 之前）。v0.2.3 起建图改为两段式，先把原生创建阶段的工作量压到
/// 最低，缩小崩溃窗口、也便于二分定位：
///
/// - 创建段（onMapCreated 之前）：AMapWidget 只带必需参数与最简初始
///   相机（目标 + 缩放，倾斜/方位归 0）；markers、polylines、定位样式、
///   建筑/路况等一切可选参数与图层开关一律不下发（对应字段为
///   false/空）。
/// - 就绪段（onMapCreated 之后）：由这里算出完整参数集，经一次重建
///   把叠加物与图层配置全部下发（插件靠 didUpdateWidget 增量生效）。
///   兼容模式（compatMode）叠加在就绪段参数之上，行为与旧版一致。
class AmapMapStageParams {
  const AmapMapStageParams({
    required this.overlaysEnabled,
    required this.myLocationStyleEnabled,
    required this.trafficEnabled,
    required this.buildingsEnabled,
    required this.scaleEnabled,
    required this.labelsEnabled,
    required this.touchPoiEnabled,
    required this.initialTilt,
  });

  /// markers / polylines 是否下发（创建段恒 false，就绪后为 true）。
  final bool overlaysEnabled;

  /// 是否下发定位样式（创建段不下发；就绪后下发「关闭 SDK 蓝点」样式）。
  final bool myLocationStyleEnabled;

  final bool trafficEnabled;
  final bool buildingsEnabled;
  final bool scaleEnabled;
  final bool labelsEnabled;
  final bool touchPoiEnabled;

  /// 初始相机倾斜角：创建段恒 0；就绪段的参数记录取业务值
  /// （插件创建后不重读 initialCameraPosition，实际倾斜由相机命令补）。
  final double initialTilt;
}

/// 按当前阶段算出 AMapWidget 应下发的参数集。
///
/// [created] 为 onMapCreated 是否已到达；[compatMode] 为设置里的地图
/// 兼容模式；[trafficEnabled]、[tilt] 为业务侧期望值。
AmapMapStageParams resolveAmapMapStageParams({
  required bool created,
  required bool compatMode,
  required bool trafficEnabled,
  required double tilt,
}) {
  if (!created) {
    // 创建段·裸创建：除必需参数外什么都不给原生层，把 TextureMapView
    // 构造期间的渲染/叠加物初始化工作降到最低。
    return const AmapMapStageParams(
      overlaysEnabled: false,
      myLocationStyleEnabled: false,
      trafficEnabled: false,
      buildingsEnabled: false,
      scaleEnabled: false,
      labelsEnabled: false,
      touchPoiEnabled: false,
      initialTilt: 0,
    );
  }
  // 就绪段·完整参数：与 v0.2.2 以前一次性下发的语义保持一致，
  // 兼容模式在此之上再关掉可选渲染项。
  return AmapMapStageParams(
    overlaysEnabled: true,
    myLocationStyleEnabled: true,
    trafficEnabled: compatMode ? false : trafficEnabled,
    buildingsEnabled: compatMode ? false : tilt > 0,
    scaleEnabled: !compatMode,
    labelsEnabled: !compatMode,
    touchPoiEnabled: !compatMode,
    initialTilt: compatMode ? 0 : tilt,
  );
}
