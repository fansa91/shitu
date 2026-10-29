import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';

import '../models/geo_point.dart';
import '../models/poi.dart';
import '../services/settings_service.dart';

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
  });

  final SettingsService settings;
  final Poi? selectedPoi;
  final List<GeoPoint> selectedRoutePoints;
  final List<GeoPoint> alternativeRoutePoints;
  final bool trafficEnabled;

  @override
  State<AmapMapView> createState() => _AmapMapViewState();
}

class _AmapMapViewState extends State<AmapMapView> {
  AMapController? _controller;
  bool _pluginInitialized = false;

  LatLng _toLatLng(GeoPoint p) => LatLng(p.latitude, p.longitude);

  /// 在 AMapWidget 构建前把运行时 Key 与隐私同意状态注入插件。
  void _initPlugin() {
    if (_pluginInitialized) return;
    _pluginInitialized = true;
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
      _controller?.moveCamera(
        CameraUpdate.newLatLngZoom(_toLatLng(poi!.location!), 15),
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

  @override
  Widget build(BuildContext context) {
    _initPlugin();
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
      ),
      myLocationStyleOptions: MyLocationStyleOptions(true),
      trafficEnabled: widget.trafficEnabled,
      markers: markers,
      polylines: polylines,
      onMapCreated: (controller) {
        _controller = controller;
        if (widget.selectedRoutePoints.isNotEmpty) {
          _fitPoints(widget.selectedRoutePoints);
        } else if (widget.selectedPoi?.location != null) {
          controller.moveCamera(CameraUpdate.newLatLngZoom(
            _toLatLng(widget.selectedPoi!.location!),
            15,
          ));
        }
      },
    );
  }
}
