import 'package:flutter/material.dart';

import '../models/geo_point.dart';
import '../models/poi.dart';
import '../services/settings_service.dart';
import 'tile_map_view.dart';

/// 地图命令句柄：页面持有它向当前地图发命令（移相机 / 缩放）。
/// 地图就绪后注册实现（见 TileMapView.onMapReady）；未就绪时命令会被
/// 安全忽略，页面逻辑不因此崩溃。
class MapHandle {
  void Function(GeoPoint target, double? zoom, double tilt)? _moveImpl;
  void Function()? _zoomInImpl;
  void Function()? _zoomOutImpl;

  bool get isAttached => _moveImpl != null;

  void attach({
    required void Function(GeoPoint target, double? zoom, double tilt) move,
    required void Function() zoomIn,
    required void Function() zoomOut,
  }) {
    _moveImpl = move;
    _zoomInImpl = zoomIn;
    _zoomOutImpl = zoomOut;
  }

  void detach() {
    _moveImpl = null;
    _zoomInImpl = null;
    _zoomOutImpl = null;
  }

  /// 移动相机到 [target]（GCJ-02）；zoom 为 null 时保持当前缩放。
  /// tilt 为旧原生底图接口保留：瓦片底图是 2D 平面图，实现侧忽略。
  void moveCamera(GeoPoint target, {double? zoom, double tilt = 0}) =>
      _moveImpl?.call(target, zoom, tilt);

  void zoomIn() => _zoomInImpl?.call();
  void zoomOut() => _zoomOutImpl?.call();
}

/// 地图区域的统一入口：全平台统一用瓦片底图（flutter_map + 高德 Web
/// 瓦片，见 TileMapView），底图不需要任何 Key、不初始化原生 SDK。
///
/// 历史：v0.2.x 曾在此按「移动端 + 隐私同意 + SDK Key」条件切换高德
/// 原生底图、否则回退示意地图（FakeMap），并带崩溃自保守卫；原生渲染
/// 器在目标机型上必崩后整套机制随底图切换一并退役（2026-10-30）。
class AppMap extends StatelessWidget {
  const AppMap({
    super.key,
    required this.settings,
    this.dark = false,
    this.selectedPoi,
    this.selectedRoutePoints = const [],
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

  /// 深色场景标记（导航页）：瓦片无深色变体，仅保留参数兼容旧调用，
  /// 深色观感由页面自身 UI 主题承担。
  final bool dark;

  final Poi? selectedPoi;
  final List<GeoPoint> selectedRoutePoints;
  final List<GeoPoint> alternativeRoutePoints;
  final bool trafficEnabled;

  /// 旧接口保留：原生/FakeMap 时代控制示意蓝点；瓦片底图下我的位置
  /// 只按 [myLocation] 绘制，本参数不再起作用。
  final bool showLocationDot;

  /// 命令句柄（可选）：传入后页面可主动移动相机 / 缩放。
  final MapHandle? handle;

  /// 我的位置（GCJ-02）：底图上自绘蓝色圆点。
  final GeoPoint? myLocation;

  /// 旧接口保留：原生底图的相机倾斜角。瓦片底图为 2D 平面图，
  /// 无 3D 倾斜，本参数被忽略。
  final double tilt;

  /// 相机停稳回调：回传中心点与缩放。
  final void Function(GeoPoint center, double zoom)? onCameraSettled;

  /// 检测到用户手动拖图时回调。
  final VoidCallback? onUserDragged;

  @override
  Widget build(BuildContext context) {
    return TileMapView(
      selectedPoi: selectedPoi,
      selectedRoutePoints: selectedRoutePoints,
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
