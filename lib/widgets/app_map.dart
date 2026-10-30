import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/geo_point.dart';
import '../models/poi.dart';
import '../services/map_backend.dart';
import '../services/settings_service.dart';
import 'native_map_view.dart';
import 'tile_map_view.dart';

/// 地图命令句柄：页面持有它向当前地图发命令（移相机 / 缩放）。
/// 地图就绪后注册实现（见 TileMapView.onMapReady）；未就绪时命令会被
/// 安全忽略，页面逻辑不因此崩溃。
class MapHandle {
  void Function(GeoPoint target, double? zoom, double tilt)? _moveImpl;
  void Function()? _zoomInImpl;
  void Function()? _zoomOutImpl;
  void Function(double? headingDegrees)? _pointUpImpl;

  bool get isAttached => _moveImpl != null;

  void attach({
    required void Function(GeoPoint target, double? zoom, double tilt) move,
    required void Function() zoomIn,
    required void Function() zoomOut,
    void Function(double? headingDegrees)? pointUp,
  }) {
    _moveImpl = move;
    _zoomInImpl = zoomIn;
    _zoomOutImpl = zoomOut;
    _pointUpImpl = pointUp;
  }

  void detach() {
    _moveImpl = null;
    _zoomInImpl = null;
    _zoomOutImpl = null;
    _pointUpImpl = null;
  }

  /// 让 [headingDegrees] 方向朝上（导航车头朝上）；null = 恢复北朝上。
  /// [headingDegrees] 是「希望出现在屏幕正上方的方向」（0=正北、
  /// 顺时针为正）。各底图自行翻译成本端旋转语义（瓦片层是内容
  /// 旋转角取负；原生层是 CameraPosition.bearing 直接取该值）。
  /// 实现未提供时静默忽略（如旧实现），页面逻辑不因此崩溃。
  void pointUp(double? headingDegrees) => _pointUpImpl?.call(headingDegrees);

  /// 移动相机到 [target]（GCJ-02）；zoom 为 null 时保持当前缩放。
  /// tilt 为旧原生底图接口保留：瓦片底图是 2D 平面图，实现侧忽略。
  void moveCamera(GeoPoint target, {double? zoom, double tilt = 0}) =>
      _moveImpl?.call(target, zoom, tilt);

  void zoomIn() => _zoomInImpl?.call();
  void zoomOut() => _zoomOutImpl?.call();
}

/// 地图区域的统一入口：按平台分流后端（选择逻辑见
/// services/map_backend.dart 的 [selectMapBackend]）：
/// - iOS + 已同意隐私 + 已填 iOS Key → 原生高德地图（NativeMapView，
///   MAMapKit 渲染在 iOS 上一直正常，三期恢复；创建失败其内部
///   回落瓦片）；
/// - 其余一切情况 → 瓦片底图（TileMapView，flutter_map + 高德/腾讯
///   瓦片）。Android 恒瓦片：原生 GL 渲染器在目标机型必崩
///   （v0.2.1–v0.2.6 实锤），插件 Android 侧亦已桩化。
///
/// 历史：v0.2.x 曾在此按「移动端 + 隐私同意 + SDK Key」切换原生、
/// 否则回退示意地图（FakeMap），并带崩溃自保守卫；Android 必崩后
/// 整套机制随底图切瓦片一并退役，三期只恢复 iOS 一条原生路径，
/// 守卫/面包屑不恢复。
class AppMap extends StatelessWidget {
  const AppMap({
    super.key,
    required this.settings,
    this.dark = false,
    this.selectedPoi,
    this.selectedRoutePoints = const [],
    this.routeOutlinePoints = const [],
    this.alternativeRoutePoints = const [],
    this.trafficEnabled = false,
    this.showLocationDot = true,
    this.handle,
    this.myLocation,
    this.tilt = 0,
    this.onCameraSettled,
    this.onUserDragged,
  });

  final SettingsService settings;

  /// 深色场景标记（导航页）：不影响后端选择（iOS 导航同样走原生）；
  /// 瓦片无深色变体、原生底图自带深色模式跟随系统，深色观感主要由
  /// 页面自身 UI 主题承担。
  final bool dark;

  final Poi? selectedPoi;
  final List<GeoPoint> selectedRoutePoints;

  /// 全程剩余轮廓（导航态专用）：非空即进入导航渲染模式——
  /// [selectedRoutePoints] 按「当前路段」高亮绘制，本层以极淡色
  /// 画剩余全程；终点标记取本层末点，起点标记抑制（当前位置点
  /// 已覆盖）。规划态传空，渲染与旧版一致。
  final List<GeoPoint> routeOutlinePoints;
  final List<GeoPoint> alternativeRoutePoints;
  final bool trafficEnabled;

  /// 旧接口保留：原生/FakeMap 时代控制示意蓝点；瓦片底图下我的位置
  /// 只按 [myLocation] 绘制，本参数不再起作用。
  final bool showLocationDot;

  /// 命令句柄（可选）：传入后页面可主动移动相机 / 缩放。
  final MapHandle? handle;

  /// 我的位置（GCJ-02）：底图上自绘蓝色圆点。
  final GeoPoint? myLocation;

  /// 相机倾斜角：iOS 原生底图生效（2D=0，3D 约 58）；瓦片底图为
  /// 2D 平面图无倾斜，实现侧忽略。
  final double tilt;

  /// 相机停稳回调：回传中心点与缩放。
  final void Function(GeoPoint center, double zoom)? onCameraSettled;

  /// 检测到用户手动拖图时回调。
  final VoidCallback? onUserDragged;

  @override
  Widget build(BuildContext context) {
    final backend = selectMapBackend(
      isIOS: defaultTargetPlatform == TargetPlatform.iOS,
      privacyAgreed: settings.privacyAgreed,
      iosKey: settings.amapSdkIosKey,
    );
    if (backend == MapBackend.nativeAmap) {
      return NativeMapView(
        // iOS Key 变化 → 换掉旧 State/平台视图，按新 Key 重建。
        key: ValueKey('amap-ios-${settings.amapSdkIosKey.trim().hashCode}'),
        settings: settings,
        selectedPoi: selectedPoi,
        selectedRoutePoints: selectedRoutePoints,
        routeOutlinePoints: routeOutlinePoints,
        alternativeRoutePoints: alternativeRoutePoints,
        trafficEnabled: trafficEnabled,
        handle: handle,
        myLocation: myLocation,
        tilt: tilt,
        onCameraSettled: onCameraSettled,
        onUserDragged: onUserDragged,
      );
    }
    return TileMapView(
      selectedPoi: selectedPoi,
      selectedRoutePoints: selectedRoutePoints,
      routeOutlinePoints: routeOutlinePoints,
      alternativeRoutePoints: alternativeRoutePoints,
      trafficEnabled: trafficEnabled,
      baseStyle: settings.mapBaseStyle,
      tileSource: settings.mapTileSource,
      handle: handle,
      myLocation: myLocation,
      onCameraSettled: onCameraSettled,
      onUserDragged: onUserDragged,
    );
  }
}
