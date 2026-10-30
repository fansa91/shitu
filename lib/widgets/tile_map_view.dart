import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/geo_point.dart';
import '../models/poi.dart';
import '../services/map_tiles.dart';
import 'app_map.dart';

/// 瓦片底图（flutter_map + 高德 Web 瓦片），全平台统一实现。
///
/// 换赛道背景：高德原生 SDK 渲染器在一加 7 Pro 上两大版本、两种视图
/// 类都死在 GL 渲染器启动处（v0.2.1–v0.2.6 逐项排除 Key/签名/绑定/
/// 打包/视图类），故底图弃原生 SDK 改 Web 瓦片：无原生渲染器，不存在
/// 那类进程级崩溃；搜索/算路/定位本来就是 Dart + Web API，不受影响。
///
/// 坐标系：全量业务数据是 GCJ-02，高德瓦片亦按 GCJ-02 渲染，flutter_map
/// 用默认 EPSG:3857 直接喂 GCJ-02 即对齐（原理见 services/map_tiles.dart）。
///
/// 与旧原生实现的差异（诚实降级）：瓦片是 2D 栅格图，没有 3D 倾斜与
/// 建筑——[MapHandle.moveCamera] 的 tilt 参数被忽略；底图无深色变体，
/// 导航页深色靠其自身 UI 主题。
class TileMapView extends StatefulWidget {
  const TileMapView({
    super.key,
    this.selectedPoi,
    this.selectedRoutePoints = const [],
    this.alternativeRoutePoints = const [],
    this.trafficEnabled = false,
    this.baseStyle = MapBaseStyle.standard,
    this.handle,
    this.myLocation,
    this.onCameraSettled,
    this.onUserDragged,
  });

  final Poi? selectedPoi;
  final List<GeoPoint> selectedRoutePoints;
  final List<GeoPoint> alternativeRoutePoints;
  final bool trafficEnabled;
  final MapBaseStyle baseStyle;
  final MapHandle? handle;

  /// 我的位置（GCJ-02）：自绘蓝色圆点（与导航页 FakeMap 时代一致的画法）。
  final GeoPoint? myLocation;

  final void Function(GeoPoint center, double zoom)? onCameraSettled;
  final VoidCallback? onUserDragged;

  @override
  State<TileMapView> createState() => _TileMapViewState();
}

class _TileMapViewState extends State<TileMapView> {
  final _controller = MapController();

  /// 就绪前 MapController 命令无处落：onMapReady 后才挂句柄/补相机动作。
  bool _ready = false;

  LatLng _toLatLng(GeoPoint p) => LatLng(p.latitude, p.longitude);

  GeoPoint get _initialFocus =>
      widget.selectedPoi?.location ??
      (widget.selectedRoutePoints.isNotEmpty
          ? widget.selectedRoutePoints.first
          : null) ??
      const GeoPoint(latitude: 22.54554, longitude: 114.05769); // 深圳市中心

  bool get _hasFittableRoute => widget.selectedRoutePoints.length > 1;

  @override
  void didUpdateWidget(covariant TileMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ready) return;
    // 选中的 POI 变化 → 相机移动过去。
    final poi = widget.selectedPoi;
    if (poi?.location != null && poi?.id != oldWidget.selectedPoi?.id) {
      _controller.move(_toLatLng(poi!.location!), 15);
    }
    // 路线出现 → 相机框住整条选中路线。
    if (widget.selectedRoutePoints.isNotEmpty &&
        oldWidget.selectedRoutePoints.isEmpty) {
      _fitPoints(widget.selectedRoutePoints);
    }
  }

  void _fitPoints(List<GeoPoint> points) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      _controller.move(_toLatLng(points.first), 15);
      return;
    }
    final bounds = LatLngBounds.fromPoints(points.map(_toLatLng).toList());
    // 全部点重合时 bounds 退化为一个点，fitCamera 无意义，改直接移动。
    if (bounds.northEast == bounds.southWest) {
      _controller.move(bounds.center, 15);
      return;
    }
    _controller.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
    );
  }

  void _handleMove(GeoPoint target, double? zoom, double tilt) {
    // tilt 忽略：瓦片底图为 2D 平面图，无倾斜（诚实降级，见类注释）。
    _controller.move(_toLatLng(target), zoom ?? _controller.camera.zoom);
  }

  void _onMapReady() {
    _ready = true;
    widget.handle?.attach(
      move: _handleMove,
      zoomIn: () => _controller.move(
        _controller.camera.center,
        _controller.camera.zoom + 1,
      ),
      zoomOut: () => _controller.move(
        _controller.camera.center,
        _controller.camera.zoom - 1,
      ),
    );
    if (widget.selectedRoutePoints.isNotEmpty) {
      _fitPoints(widget.selectedRoutePoints);
    } else if (widget.selectedPoi?.location != null) {
      _controller.move(_toLatLng(widget.selectedPoi!.location!), 15);
    }
  }

  @override
  void dispose() {
    widget.handle?.detach();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: _toLatLng(_initialFocus),
            initialZoom: widget.selectedPoi?.location != null ? 15 : 12,
            initialCameraFit: _hasFittableRoute
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(
                      widget.selectedRoutePoints.map(_toLatLng).toList(),
                    ),
                    padding: const EdgeInsets.all(60),
                  )
                : null,
            minZoom: 3,
            maxZoom: 20,
            onMapReady: _onMapReady,
            // 相机停稳（任何来源的移动结束）→ 回报中心与缩放。
            onMapEvent: (event) {
              if (event is MapEventMoveEnd) {
                final camera = _controller.camera;
                widget.onCameraSettled?.call(
                  GeoPoint(
                    latitude: camera.center.latitude,
                    longitude: camera.center.longitude,
                  ),
                  camera.zoom,
                );
              }
            },
            // 用户手势引起的相机变化 → 通知页面（解除跟随锁定）。
            onPositionChanged: (camera, hasGesture) {
              if (hasGesture) widget.onUserDragged?.call();
            },
          ),
          children: [
            TileLayer(
              urlTemplate: widget.baseStyle == MapBaseStyle.satellite
                  ? AmapTileTemplates.satellite
                  : AmapTileTemplates.standard,
              subdomains: AmapTileTemplates.subdomains,
              userAgentPackageName: 'com.shitu.app',
              maxNativeZoom: AmapTileTemplates.maxNativeZoom,
            ),
            if (widget.baseStyle == MapBaseStyle.satellite)
              TileLayer(
                urlTemplate: AmapTileTemplates.satelliteLabels,
                subdomains: AmapTileTemplates.subdomains,
                userAgentPackageName: 'com.shitu.app',
                maxNativeZoom: AmapTileTemplates.maxNativeZoom,
                // 个别瓦片取不到时保持透明，不挡下面的卫星影像。
                errorTileCallback: (_, _, _) {},
              ),
            if (widget.trafficEnabled)
              TileLayer(
                urlTemplate: AmapTileTemplates.traffic,
                userAgentPackageName: 'com.shitu.app',
                maxNativeZoom: AmapTileTemplates.maxNativeZoom,
                // 无路况数据区域端点回 404：吞掉，保持透明（见 map_tiles 实测）。
                errorTileCallback: (_, _, _) {},
              ),
            if (widget.alternativeRoutePoints.length > 1 ||
                widget.selectedRoutePoints.length > 1)
              PolylineLayer(
                polylines: [
                  if (widget.alternativeRoutePoints.length > 1)
                    Polyline(
                      points: widget.alternativeRoutePoints
                          .map(_toLatLng)
                          .toList(),
                      color: const Color(0xFF9AA0A6),
                      strokeWidth: 7,
                    ),
                  if (widget.selectedRoutePoints.length > 1)
                    Polyline(
                      points: widget.selectedRoutePoints
                          .map(_toLatLng)
                          .toList(),
                      color: const Color(0xFF1A73E8),
                      strokeWidth: 7,
                      borderColor: Colors.white,
                      borderStrokeWidth: 2.5,
                    ),
                ],
              ),
            MarkerLayer(markers: _buildMarkers()),
          ],
        ),
        // 底图版权标注（高德瓦片要求来源可见）。
        const Positioned(
          right: 8,
          bottom: 6,
          child: IgnorePointer(
            child: Text(
              '© 高德地图',
              style: TextStyle(
                fontSize: 10,
                color: Color(0x99000000),
                shadows: [Shadow(color: Color(0xCCFFFFFF), blurRadius: 3)],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    return [
      if (widget.selectedRoutePoints.isNotEmpty)
        Marker(
          point: _toLatLng(widget.selectedRoutePoints.first),
          width: 18,
          height: 18,
          child: _dotMarker(const Color(0xFF34A853)),
        ),
      if (widget.selectedRoutePoints.isNotEmpty)
        Marker(
          point: _toLatLng(widget.selectedRoutePoints.last),
          width: 36,
          height: 36,
          alignment: Alignment.bottomCenter,
          child: const Icon(
            Icons.location_pin,
            color: Color(0xFFE8453C),
            size: 36,
          ),
        ),
      if (widget.selectedPoi?.location != null)
        Marker(
          point: _toLatLng(widget.selectedPoi!.location!),
          width: 200,
          height: 76,
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 4),
                  ],
                ),
                child: Text(
                  widget.selectedPoi!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ),
              const Icon(
                Icons.location_pin,
                color: Color(0xFFE8453C),
                size: 38,
              ),
            ],
          ),
        ),
      if (widget.myLocation != null)
        Marker(
          point: _toLatLng(widget.myLocation!),
          width: 44,
          height: 44,
          child: _myLocationDot(),
        ),
    ];
  }

  Widget _dotMarker(Color color) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2.5),
      ),
    );
  }

  Widget _myLocationDot() {
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0x331A73E8),
      ),
      child: Center(
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1A73E8),
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
      ),
    );
  }
}
