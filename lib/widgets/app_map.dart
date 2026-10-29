import 'package:flutter/material.dart';

import '../models/geo_point.dart';
import '../models/poi.dart';
import '../services/amap_sdk_service.dart';
import '../services/map_crash_guard.dart';
import '../services/settings_service.dart';
import 'amap_map_view.dart';
import 'fake_map.dart';

/// 地图命令句柄：页面持有它向当前地图发命令（移相机 / 缩放）。
/// 真实高德地图创建后注册实现；假地图（桌面端 / 无 Key / 未同意隐私）
/// 不注册，命令会被安全忽略，页面逻辑不因此崩溃。
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
  void moveCamera(GeoPoint target, {double? zoom, double tilt = 0}) =>
      _moveImpl?.call(target, zoom, tilt);

  void zoomIn() => _zoomInImpl?.call();
  void zoomOut() => _zoomOutImpl?.call();
}

/// 地图区域的统一入口：
/// 满足「移动端 + 已隐私同意 + SDK 已初始化 + 当前平台 Key 已填」
/// 时用真实高德地图，否则回退 [FakeMap]（桌面端、无 Key、未同意隐私）。
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
    this.crashGuard,
    this.onCameraSettled,
    this.onUserDragged,
  });

  final SettingsService settings;
  final bool dark;
  final Poi? selectedPoi;
  final List<GeoPoint> selectedRoutePoints;
  final List<GeoPoint> alternativeRoutePoints;
  final bool trafficEnabled;
  final bool showLocationDot;

  /// 命令句柄（可选）：传入后页面可主动移动相机 / 缩放。
  final MapHandle? handle;

  /// 我的位置（GCJ-02）：真实地图上自绘蓝色标记（不用 SDK 蓝点，避免叠加）。
  final GeoPoint? myLocation;

  /// 相机倾斜角：0 = 2D，约 58 = 3D。
  final double tilt;

  /// 地图崩溃面包屑/自保（可选）：自保触发时本组件直接回落 [FakeMap]
  /// 并挂横幅，不再尝试创建真实地图，避免崩溃循环。
  final MapCrashGuard? crashGuard;

  /// 相机停稳回调：回传中心点与缩放（页面据此保持 2D/3D 与跟随状态）。
  final void Function(GeoPoint center, double zoom)? onCameraSettled;

  /// 检测到用户手动拖图（相机停在非程序设定的位置）时回调。
  final VoidCallback? onUserDragged;

  @override
  Widget build(BuildContext context) {
    final guard = crashGuard;
    if (!dark && guard != null && guard.guardTripped) {
      return _guardFallback(guard);
    }
    if (!dark && AmapSdkService.instance.canShowRealMap(settings)) {
      return AmapMapView(
        // Key 变化 → 换掉旧 State/平台视图，先销毁旧图再按新 Key 初始化。
        key: ValueKey('amap-${AmapSdkService.instance.keyIdFor(settings)}'),
        settings: settings,
        selectedPoi: selectedPoi,
        selectedRoutePoints: selectedRoutePoints,
        alternativeRoutePoints: alternativeRoutePoints,
        trafficEnabled: trafficEnabled,
        handle: handle,
        myLocation: myLocation,
        tilt: tilt,
        crashGuard: guard,
        compatMode: settings.mapCompatMode,
        onCameraSettled: onCameraSettled,
        onUserDragged: onUserDragged,
      );
    }
    return FakeMap(
      dark: dark,
      showRoute: selectedRoutePoints.isNotEmpty,
      showDestinationPin: selectedPoi != null,
      showLocationDot: showLocationDot,
    );
  }

  /// 自保回落：上一轮死在建图过程中，本轮不再碰真实地图，
  /// 横幅把停留步骤说清，并指引去设置重试（可先开兼容模式）。
  Widget _guardFallback(MapCrashGuard guard) {
    final stopped = guard.stoppedAt?.label ?? '未知步骤';
    return Stack(
      children: [
        Positioned.fill(
          child: FakeMap(
            showRoute: selectedRoutePoints.isNotEmpty,
            showDestinationPin: selectedPoi != null,
            showLocationDot: showLocationDot,
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: Material(
            color: Colors.amber.shade100,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                '上次打开真实地图时崩溃（停在步骤：$stopped），已自动切换示意地图。'
                '可在设置中开启「地图兼容模式」后点「重试真实地图」再试。',
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
