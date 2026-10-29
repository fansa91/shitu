import 'package:flutter/material.dart';

import '../models/geo_point.dart';
import '../models/poi.dart';
import '../services/amap_sdk_service.dart';
import '../services/settings_service.dart';
import 'amap_map_view.dart';
import 'fake_map.dart';

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
  });

  final SettingsService settings;
  final bool dark;
  final Poi? selectedPoi;
  final List<GeoPoint> selectedRoutePoints;
  final List<GeoPoint> alternativeRoutePoints;
  final bool trafficEnabled;
  final bool showLocationDot;

  @override
  Widget build(BuildContext context) {
    if (!dark && AmapSdkService.instance.canShowRealMap(settings)) {
      return AmapMapView(
        settings: settings,
        selectedPoi: selectedPoi,
        selectedRoutePoints: selectedRoutePoints,
        alternativeRoutePoints: alternativeRoutePoints,
        trafficEnabled: trafficEnabled,
      );
    }
    return FakeMap(
      dark: dark,
      showRoute: selectedRoutePoints.isNotEmpty,
      showDestinationPin: selectedPoi != null,
      showLocationDot: showLocationDot,
    );
  }
}
