import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';

import '../models/geo_point.dart';
import '../models/poi.dart';
import '../services/amap_map_params.dart';
import '../services/amap_sdk_service.dart';
import '../services/map_crash_guard.dart';
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
    this.crashGuard,
    this.compatMode = false,
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

  /// 崩溃面包屑/自保（可选）：建图链路逐点落盘，原生崩溃后下次启动据此
  /// 定位停在哪一步并自动回落示意地图。为空时不记录、不影响功能。
  final MapCrashGuard? crashGuard;

  /// 兼容模式：只用最保守渲染配置建图（关建筑/路况/指南针/比例尺/
  /// 标注/POI 点击、相机不倾斜），排查原生渲染崩溃时用。
  final bool compatMode;

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

  /// 「地图创建开始」面包屑只落一次（build 可能多次执行）。
  bool _createMarked = false;

  /// 两段式建图的就绪门控：onMapCreated 到达前，AMapWidget 只带
  /// 裸创建参数（见 [resolveAmapMapStageParams]）；到达后置 true，
  /// 经一次重建把叠加物与完整图层配置下发。
  bool _created = false;

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
    // 面包屑第一步在调插件初始化之前落盘：若原生初始化本身崩，
    // 下一轮启动能看到序列停在 sdk_init_start。
    widget.crashGuard?.markStep(MapBreadcrumbStep.sdkInitStart);
    _initFuture = AmapSdkService.instance.runPluginInit(
      widget.settings,
      () async => _doPluginInit(),
    );
    _initFuture.then((ok) {
      if (ok) {
        widget.crashGuard?.markStep(MapBreadcrumbStep.sdkInitDone);
      } else {
        // 初始化在 Dart 层失败并已回落示意地图：本轮安全收尾，
        // 落一个正常销毁标记，避免下一轮被误判为原生崩溃触发自保。
        widget.crashGuard?.markStep(MapBreadcrumbStep.mapDisposedClean);
      }
    });
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
    // 能走到 dispose 说明 Flutter 正常拆除了地图（原生崩溃时进程直接
    // 死、不会有这一步），落正常销毁标记给下一轮自保判定。
    widget.crashGuard?.markStep(MapBreadcrumbStep.mapDisposedClean);
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
    // 两段式下发参数：创建段（_created 前）只裸创建，就绪段下发全量。
    final stage = resolveAmapMapStageParams(
      created: _created,
      compatMode: widget.compatMode,
      trafficEnabled: widget.trafficEnabled,
      tilt: widget.tilt,
    );
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
    final initialTarget = focus != null
        ? _toLatLng(focus)
        : const LatLng(22.54554, 114.05769); // 深圳市中心
    // 面包屑：即将把创建参数交给原生 TextureMapView——原生崩溃最可能
    // 发生在这一步到 onMapCreated 之间，序列停在这里即指向该窗口。
    if (!_createMarked) {
      _createMarked = true;
      widget.crashGuard?.markStep(MapBreadcrumbStep.mapCreateStart);
    }
    return AMapWidget(
      // 创建段最简初始相机：只有目标 + 缩放，倾斜/方位归 0；
      // 就绪段插件不再重读此参数，倾斜在 onMapCreated 里用相机命令补。
      initialCameraPosition: CameraPosition(
        target: initialTarget,
        zoom: 12,
        tilt: stage.initialTilt,
      ),
      // 关闭 SDK 自带蓝点：位置由 geolocator 提供并自绘标记，避免双蓝点。
      // 创建段不下发定位样式（保持裸创建），就绪段再下发。
      myLocationStyleOptions:
          stage.myLocationStyleEnabled ? MyLocationStyleOptions(false) : null,
      // 兼容模式：关掉一切可选渲染项（建筑/路况/指南针/比例尺/标注/
      // POI 点击），只留最基础的底图；手势保持插件默认不动，
      // 创建段与就绪段一致（插件默认全开，本工程从不覆写）。
      // 注：插件 1.0.15 未公开室内图/缩放控件开关，无从设置。
      trafficEnabled: stage.trafficEnabled,
      buildingsEnabled: stage.buildingsEnabled,
      compassEnabled: false,
      scaleEnabled: stage.scaleEnabled,
      labelsEnabled: stage.labelsEnabled,
      touchPoiEnabled: stage.touchPoiEnabled,
      markers: stage.overlaysEnabled ? markers : const <Marker>{},
      polylines: stage.overlaysEnabled ? polylines : const <Polyline>{},
      onCameraMoveEnd: _onCameraMoveEnd,
      onMapCreated: (controller) {
        widget.crashGuard?.markStep(MapBreadcrumbStep.onMapCreated);
        // 再过一帧仍活着，才算真正迈过建图崩溃窗口。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.crashGuard?.markStep(MapBreadcrumbStep.firstFrame);
          }
        });
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
        } else if (widget.tilt > 0) {
          // 裸创建时初始相机倾斜被归 0：无路线/POI 抢相机时，在这里
          // 把业务倾斜（如主页 3D 模式）用相机命令补回来，保持旧行为。
          _expectedTarget = initialTarget;
          controller.moveCamera(CameraUpdate.newCameraPosition(
            CameraPosition(target: initialTarget, zoom: 12, tilt: widget.tilt),
          ));
        }
        // 迈过原生创建窗口：置就绪门控，触发一次重建把完整参数集
        // （叠加物、图层、定位样式）下发，插件经 didUpdateWidget 生效。
        if (mounted && !_created) {
          setState(() => _created = true);
        }
      },
    );
  }
}
