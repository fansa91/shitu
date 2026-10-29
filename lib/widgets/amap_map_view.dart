import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';

import '../models/geo_point.dart';
import '../models/poi.dart';
import '../services/amap_sdk_service.dart';
import '../services/settings_service.dart';
import 'app_map.dart';
import 'fake_map.dart';

/// 真实高德地图（社区维护 fork `amap_map`，基于官方插件演进）。
/// 只在隐私已同意、SDK 已就绪、当前平台 Key 已填时由 AppMap 选用。
///
/// Key 与隐私声明在首次构建前经 AMapInitializer 注入：Key 运行时从
/// SettingsService 读取，绝不硬编码；本 Widget 只会在用户已同意隐私
/// 后才被构建（见 HomeScreen 的隐私流程与 AmapSdkService 的门控）。
///
/// 本文件是全工程唯一 import 高德插件的地方。
class AmapMapView extends StatefulWidget {
  const AmapMapView({
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

  /// 我的位置（GCJ-02）：自绘蓝色标记。SDK 自带蓝点已关闭，避免两个蓝点叠加。
  final GeoPoint? myLocation;

  /// 相机倾斜角：0 = 2D，约 58 = 3D。
  final double tilt;

  final void Function(GeoPoint center, double zoom)? onCameraSettled;
  final VoidCallback? onUserDragged;

  @override
  State<AmapMapView> createState() => _AmapMapViewState();
}

class _AmapMapViewState extends State<AmapMapView> {
  AMapController? _controller;

  /// 插件初始化门控 Future：成功后才允许创建 AMapWidget（见 initState）。
  late final Future<bool> _initFuture;

  /// 最近一次已知的缩放（onCameraMoveEnd 回报），命令未指定 zoom 时沿用。
  double _lastZoom = 12;

  /// 程序主动移动相机的目标点。相机停稳后若实际中心明显偏离它，
  /// 判定为用户手动拖图（触发 onUserDragged，用于解除跟随锁定）。
  LatLng? _expectedTarget;

  LatLng _toLatLng(GeoPoint p) => LatLng(p.latitude, p.longitude);

  @override
  void initState() {
    super.initState();
    // 冷启动加固：不在 build() 里做初始化副作用。插件初始化经
    // AmapSdkService 的门控单飞执行，完成前绝不创建 AMapWidget，
    // 消除「冷启动带着已存 Key 直达建图」时初始化与建图的竞态；
    // Key 变化时 AppMap 用 ValueKey 换掉本 State，旧图先销毁再走新一轮。
    _initFuture = AmapSdkService.instance.runPluginInit(
      widget.settings,
      () async => _doPluginInit(),
    );
  }

  /// 把运行时 Key 与隐私同意状态注入插件（由门控保证同一 Key 只跑一次）。
  void _doPluginInit() {
    AMapInitializer.updatePrivacyAgree(
      const AMapPrivacyStatement(
        hasContains: true,
        hasShow: true,
        hasAgree: true, // 能走到这里说明用户已在首启对话框同意
      ),
    );
    AMapInitializer.init(
      context,
      apiKey: AMapApiKey(
        androidKey: widget.settings.amapSdkAndroidKey.trim(),
        iosKey: widget.settings.amapSdkIosKey.trim(),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant AmapMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
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
        CameraPosition(
          target: latLng,
          zoom: zoom ?? _lastZoom,
          tilt: tilt,
        ),
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
    widget.handle?.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: Color(0xFFE8EEF4),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('地图加载中…'),
                ],
              ),
            ),
          );
        }
        if (snapshot.data == true) return _buildRealMap(context);
        return _buildInitFallback();
      },
    );
  }

  /// 插件初始化失败：回落示意地图 + 顶部横幅写明原因（含诊断信息，
  /// 方便用户反馈时直接报出来），不白屏、不连累页面其他功能。
  Widget _buildInitFallback() {
    final reason = AmapSdkService.instance.lastInitError ?? '未知原因';
    return Stack(
      children: [
        Positioned.fill(
          child: FakeMap(
            showRoute: widget.selectedRoutePoints.isNotEmpty,
            showDestinationPin: widget.selectedPoi != null,
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
                '高德地图加载失败，已切换示意地图。原因：$reason',
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRealMap(BuildContext context) {
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
    final focus = widget.selectedPoi?.location ??
        (widget.selectedRoutePoints.isNotEmpty
            ? widget.selectedRoutePoints.first
            : null);
    return AMapWidget(
      initialCameraPosition: CameraPosition(
        target: focus != null
            ? _toLatLng(focus)
            : const LatLng(22.54554, 114.05769), // 深圳市中心
        zoom: 12,
        tilt: widget.tilt,
      ),
      // 关闭 SDK 自带蓝点：位置由 geolocator 提供并自绘标记，避免双蓝点。
      myLocationStyleOptions: MyLocationStyleOptions(false),
      trafficEnabled: widget.trafficEnabled,
      buildingsEnabled: widget.tilt > 0,
      markers: markers,
      polylines: polylines,
      onCameraMoveEnd: _onCameraMoveEnd,
      onMapCreated: (controller) {
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
          controller.moveCamera(CameraUpdate.newLatLngZoom(
            _toLatLng(widget.selectedPoi!.location!),
            15,
          ));
        }
      },
    );
  }
}
