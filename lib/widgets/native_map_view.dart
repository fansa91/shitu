import 'dart:async';

import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:flutter/material.dart';

import '../models/geo_point.dart';
import '../models/poi.dart';
import '../services/settings_service.dart';
import 'app_map.dart';
import 'tile_map_view.dart';

/// iOS 原生高德地图（官方插件 `amap_flutter_map` 3.0.0 的 vendoring 版，
/// 源码在 `packages/amap_flutter_map`，补丁清单见该包 VENDORED.md）。
///
/// 只在 iOS 且已同意隐私、已填 iOS Key 时由 AppMap 选用（选择逻辑见
/// services/map_backend.dart）：iOS 的 MAMapKit/Metal 渲染在用户设备
/// 上一直正常，崩的只有 Android GL 渲染器——本 Widget 永远不会在
/// Android 上被构建，插件的 Android 侧也已桩化（不注册视图、无 SDK
/// 依赖），双保险。
///
/// Key 与隐私声明经 AMapWidget 的 apiKey / privacyStatement 创建参数
/// 注入：原生工厂在构造地图前调用 setApiKey 与隐私三件套；Key 只从
/// 设置现读现传，绝不硬编码；隐私声明 hasAgree=true 的前提是 AppMap
/// 已确认用户同意（未同意根本不会走到这里）。
///
/// 能力面对齐当前 AppMap 接口（与 TileMapView 等价）：初始相机 /
/// POI 与路线 fit、move/zoom 句柄、选中 POI 标记、双方案折线、
/// 起终点、我的位置标记（关闭 SDK 蓝点、自绘 azure 标记防叠加）、
/// 路况开关、相机停稳回调、用户拖图判定。退役前实现里的崩溃守卫/
/// 面包屑/两段式参数/初始化门控是 Android 排查工具，**不恢复**；
/// 创建失败的兜底是 [onMapCreated] 超时未达 → 回落瓦片（见下）。
///
/// 本文件是全工程唯一 import 高德插件的地方。
class NativeMapView extends StatefulWidget {
  const NativeMapView({
    super.key,
    required this.settings,
    this.selectedPoi,
    this.selectedRoutePoints = const [],
    this.alternativeRoutePoints = const [],
    this.trafficEnabled = false,
    this.handle,
    this.myLocation,
    this.tilt = 0,
    this.onCameraSettled,
    this.onUserDragged,
  });

  final SettingsService settings;
  final Poi? selectedPoi;
  final List<GeoPoint> selectedRoutePoints;
  final List<GeoPoint> alternativeRoutePoints;
  final bool trafficEnabled;
  final MapHandle? handle;

  /// 我的位置（GCJ-02）：自绘 azure 标记。SDK 自带蓝点已关闭，避免叠加。
  final GeoPoint? myLocation;

  /// 相机倾斜角：0 = 2D，约 58 = 3D（原生底图支持倾斜）。
  final double tilt;

  final void Function(GeoPoint center, double zoom)? onCameraSettled;
  final VoidCallback? onUserDragged;

  @override
  State<NativeMapView> createState() => _NativeMapViewState();
}

class _NativeMapViewState extends State<NativeMapView> {
  AMapController? _controller;

  /// onMapCreated 是否已到达（到达前 AMapWidget 还在原生创建中）。
  bool _created = false;

  /// 创建超时兜底：onMapCreated 迟迟未达（原生创建失败）→ 回落瓦片。
  /// 插件 3.0.0 没有创建失败回调，这是 Dart 侧唯一可感知的信号。
  bool _creationFailed = false;
  Timer? _creationTimer;

  /// 最近一次已知的缩放（onCameraMoveEnd 回报），命令未指定 zoom 时沿用。
  double _lastZoom = 12;

  /// 程序主动移动相机的目标点。相机停稳后若实际中心明显偏离它，
  /// 判定为用户手动拖图（触发 onUserDragged，用于解除跟随锁定）。
  LatLng? _expectedTarget;

  LatLng _toLatLng(GeoPoint p) => LatLng(p.latitude, p.longitude);

  @override
  void initState() {
    super.initState();
    _creationTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && !_created) {
        setState(() => _creationFailed = true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant NativeMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_creationFailed) return; // 已回落瓦片，相机动作由瓦片视图负责
    // 选中的 POI 变化 → 相机移动过去。
    final poi = widget.selectedPoi;
    if (poi?.location != null && poi?.id != oldWidget.selectedPoi?.id) {
      _expectedTarget = _toLatLng(poi!.location!);
      _controller?.moveCamera(
        CameraUpdate.newLatLngZoom(_toLatLng(poi.location!), 15),
      );
    }
    // 路线出现 → 相机框住整条选中路线。
    if (widget.selectedRoutePoints.isNotEmpty &&
        oldWidget.selectedRoutePoints.isEmpty) {
      _fitPoints(widget.selectedRoutePoints);
    }
  }

  void _fitPoints(List<GeoPoint> points) {
    if (_controller == null || points.isEmpty) return;
    // 框选路线的最终中心由 bounds 决定，不做拖图判定。
    _expectedTarget = null;
    var minLat = points.first.latitude, maxLat = points.first.latitude;
    var minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }
    _controller!.moveCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
  }

  void _handleMove(GeoPoint target, double? zoom, double tilt) {
    final controller = _controller;
    if (controller == null) return;
    final latLng = _toLatLng(target);
    _expectedTarget = latLng;
    controller.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: latLng, zoom: zoom ?? _lastZoom, tilt: tilt),
      ),
    );
  }

  void _onCameraMoveEnd(CameraPosition position) {
    _lastZoom = position.zoom;
    widget.onCameraSettled?.call(
      GeoPoint(
        latitude: position.target.latitude,
        longitude: position.target.longitude,
      ),
      position.zoom,
    );
    final expected = _expectedTarget;
    if (expected == null) return;
    final dLat = (position.target.latitude - expected.latitude).abs();
    final dLng = (position.target.longitude - expected.longitude).abs();
    // 约 60 米以上偏差视为用户把地图拖走了（动画落点误差远小于此）。
    if (dLat > 0.0006 || dLng > 0.0006) {
      _expectedTarget = null;
      widget.onUserDragged?.call();
    }
  }

  @override
  void dispose() {
    _creationTimer?.cancel();
    // 句柄只在本视图真正接管过（onMapCreated 已达）时才摘：
    // 创建失败回落瓦片后句柄归瓦片视图，别把它误摘。
    if (_created) widget.handle?.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_creationFailed) {
      // 原生创建失败：整面回落瓦片底图（参数与 AppMap 的瓦片分支一致）。
      return TileMapView(
        selectedPoi: widget.selectedPoi,
        selectedRoutePoints: widget.selectedRoutePoints,
        alternativeRoutePoints: widget.alternativeRoutePoints,
        trafficEnabled: widget.trafficEnabled,
        baseStyle: widget.settings.mapBaseStyle,
        tileSource: widget.settings.mapTileSource,
        handle: widget.handle,
        myLocation: widget.myLocation,
        onCameraSettled: widget.onCameraSettled,
        onUserDragged: widget.onUserDragged,
      );
    }
    final markers = <Marker>{
      if (widget.selectedPoi?.location != null)
        Marker(
          position: _toLatLng(widget.selectedPoi!.location!),
          infoWindow: InfoWindow(title: widget.selectedPoi!.name),
        ),
      if (widget.selectedRoutePoints.isNotEmpty)
        Marker(position: _toLatLng(widget.selectedRoutePoints.first)),
      if (widget.selectedRoutePoints.isNotEmpty)
        Marker(position: _toLatLng(widget.selectedRoutePoints.last)),
      if (widget.myLocation != null)
        Marker(
          position: _toLatLng(widget.myLocation!),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: '我的位置'),
        ),
    };
    final polylines = <Polyline>{
      if (widget.alternativeRoutePoints.length > 1)
        Polyline(
          points: widget.alternativeRoutePoints.map(_toLatLng).toList(),
          color: Colors.grey,
          width: 8,
        ),
      if (widget.selectedRoutePoints.length > 1)
        Polyline(
          points: widget.selectedRoutePoints.map(_toLatLng).toList(),
          color: const Color(0xFF1A73E8),
          width: 10,
        ),
    };
    final focus =
        widget.selectedPoi?.location ??
        (widget.selectedRoutePoints.isNotEmpty
            ? widget.selectedRoutePoints.first
            : null);
    final initialTarget = focus != null
        ? _toLatLng(focus)
        : const LatLng(22.54554, 114.05769); // 深圳市中心
    return AMapWidget(
      // 运行时 Key / 隐私注入（见类注释）。Android Key 在此传空串：
      // 本视图只在 iOS 构建，插件 iOS 工厂只读 iosKey；Android 定位
      // 用的 Key 由定位桥单独下发，与地图无关。
      apiKey: AMapApiKey(
        androidKey: '',
        iosKey: widget.settings.amapSdkIosKey.trim(),
      ),
      privacyStatement: const AMapPrivacyStatement(
        hasContains: true,
        hasShow: true,
        hasAgree: true, // 前提：AppMap 已确认用户在设置里同意
      ),
      initialCameraPosition: CameraPosition(
        target: initialTarget,
        zoom: 12,
        tilt: widget.tilt,
      ),
      // 关闭 SDK 自带蓝点：位置由定位服务提供并自绘标记，避免双蓝点。
      myLocationStyleOptions: MyLocationStyleOptions(false),
      trafficEnabled: widget.trafficEnabled,
      buildingsEnabled: widget.tilt > 0,
      compassEnabled: false,
      scaleEnabled: true,
      labelsEnabled: true,
      touchPoiEnabled: true,
      markers: markers,
      polylines: polylines,
      onCameraMoveEnd: _onCameraMoveEnd,
      onMapCreated: (controller) {
        _created = true;
        _creationTimer?.cancel();
        _controller = controller;
        widget.handle?.attach(
          move: _handleMove,
          zoomIn: () => controller.moveCamera(CameraUpdate.zoomIn()),
          zoomOut: () => controller.moveCamera(CameraUpdate.zoomOut()),
        );
        if (widget.selectedRoutePoints.isNotEmpty) {
          _fitPoints(widget.selectedRoutePoints);
        } else if (widget.selectedPoi?.location != null) {
          _expectedTarget = _toLatLng(widget.selectedPoi!.location!);
          controller.moveCamera(
            CameraUpdate.newLatLngZoom(
              _toLatLng(widget.selectedPoi!.location!),
              15,
            ),
          );
        }
      },
    );
  }
}
