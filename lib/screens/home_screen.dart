import 'dart:async';

import 'package:flutter/material.dart';

import '../models/geo_point.dart';
import '../models/map_provider.dart';
import '../models/offline_route.dart';
import '../models/poi.dart';
import '../services/amap_sdk_service.dart';
import '../services/location_service.dart';
import '../services/map_data_service.dart';
import '../services/map_data_services.dart';
import '../services/places_service.dart';
import '../services/settings_service.dart';
import '../utils/format.dart';
import '../widgets/app_map.dart';
import '../widgets/poi_detail_panel.dart';
import 'offline_route_screen.dart';
import 'route_screen.dart';
import 'saved_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// 主页：全屏地图 + 悬浮搜索栏 + 数据源芯片 + 右侧控件 + 底部面板。
/// 宽度 >=900 时切换为左栏面板 + 右地图双栏。
/// 底图满足条件时为真实高德地图，否则回退假地图（见 AppMap）。
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.settings,
    required this.services,
    required this.places,
  });

  final SettingsService settings;
  final MapDataServices services;
  final PlacesService places;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _sheetController = DraggableScrollableController();
  final _mapHandle = MapHandle();
  final _locationService = LocationService();
  final _followLock = FollowLock();

  Poi? _selectedPoi;
  bool _trafficOn = true;
  bool _privacyPromptShown = false;

  /// 我的位置（GCJ-02），定位成功后有值。
  GeoPoint? _myLocation;
  bool _locating = false;
  bool _is3d = false;
  GeoPoint? _cameraCenter;
  StreamSubscription<GeoPoint>? _followSub;

  SettingsService get _settings => widget.settings;
  PlacesService get _places => widget.places;
  double get _tilt => _is3d ? 58 : 0;

  @override
  void initState() {
    super.initState();
    _places.addListener(_onPlacesChanged);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _initAmapWithPrivacy());
  }

  void _onPlacesChanged() {
    if (mounted) setState(() {});
  }

  /// 隐私合规顺序：先征得用户同意，才允许初始化高德 SDK；
  /// 不同意（或非移动端）则不初始化，地图全程回退假地图。
  Future<void> _initAmapWithPrivacy() async {
    if (!mounted) return;
    if (_settings.privacyAgreed) {
      await AmapSdkService.instance.initialize(_settings);
      if (mounted) setState(() {});
      return;
    }
    if (!AmapSdkService.instance.isMobilePlatform || _privacyPromptShown) {
      return;
    }
    _privacyPromptShown = true;
    final agreed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('隐私与高德地图 SDK'),
            content: const Text(
              '识途使用高德地图 SDK 提供地图显示与定位服务，SDK 会按其隐私政策'
              '收集设备与位置信息。只有你同意后，我们才会初始化地图 SDK 并'
              '加载你在设置中填写的 SDK Key；不同意则使用示意地图，'
              '搜索与算路（Web API）不受影响。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('不同意'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('同意并继续'),
              ),
            ],
          ),
        ) ??
        false;
    if (!agreed || !mounted) return;
    await _settings.setPrivacyAgreed(true);
    await AmapSdkService.instance.initialize(_settings);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _places.removeListener(_onPlacesChanged);
    _followSub?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- 定位与跟随 ----------

  Future<void> _onLocate() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final point = await _locationService.currentLocation();
      if (!mounted) return;
      setState(() => _myLocation = point);
      _followLock.lock();
      _mapHandle.moveCamera(point, zoom: 16, tilt: _tilt);
      _startFollowStream();
    } on LocationException catch (e) {
      if (mounted) _showLocationError(e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _startFollowStream() {
    _followSub ??= _locationService.followStream().listen(
      (point) {
        if (!mounted) return;
        setState(() => _myLocation = point);
        if (_followLock.following) {
          _mapHandle.moveCamera(point, tilt: _tilt);
        }
      },
      onError: (Object e) {
        _followSub?.cancel();
        _followSub = null;
        _followLock.unlock();
        if (mounted && e is LocationException) _showLocationError(e);
      },
    );
  }

  void _showLocationError(LocationException e) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(e.message),
        duration: const Duration(seconds: 5),
        action: e.needsSettings
            ? SnackBarAction(
                label: '去设置',
                onPressed: () {
                  if (e.kind == LocationErrorKind.serviceDisabled) {
                    _locationService.openLocationSettings();
                  } else {
                    _locationService.openAppSettings();
                  }
                },
              )
            : e.kind == LocationErrorKind.permissionDenied
                ? SnackBarAction(label: '重试', onPressed: _onLocate)
                : null,
      ),
    );
  }

  /// 地图停稳：记住中心，供 2D/3D 切换时保持视角。
  void _onCameraSettled(GeoPoint center, double zoom) {
    _cameraCenter = center;
  }

  /// 用户手动拖图 → 解除跟随锁定（定位按钮随之变回未锁定态）。
  void _onUserDragged() {
    if (_followLock.following) {
      _followLock.unlockByUserGesture();
      if (mounted) setState(() {});
    }
  }

  void _toggle3d() {
    setState(() => _is3d = !_is3d);
    final center = _cameraCenter ?? _myLocation ?? _selectedPoi?.location;
    if (center != null) {
      _mapHandle.moveCamera(center, tilt: _tilt);
    }
  }

  // ---------- 导航 ----------

  void _selectPoi(Poi poi) {
    setState(() => _selectedPoi = poi);
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        0.48,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _openSearch() async {
    final poi = await Navigator.of(context).push<Poi>(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          settings: _settings,
          services: widget.services,
        ),
      ),
    );
    if (poi != null && mounted) _selectPoi(poi);
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsScreen(settings: _settings)),
    );
  }

  void _openRoute(Poi poi) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteScreen(
          destination: poi,
          settings: _settings,
          services: widget.services,
          places: _places,
        ),
      ),
    );
  }

  void _closePoi() {
    setState(() => _selectedPoi = null);
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        0.16,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ---------- 快捷入口：家 / 公司 / 收藏 / 离线路线 ----------

  Future<void> _openHomeWork({required bool isHome}) async {
    final poi = isHome ? _places.home : _places.work;
    final label = isHome ? '家' : '公司';
    if (poi != null) {
      _selectPoi(poi);
      return;
    }
    _snack('还没设置$label：先搜一个地点，在它的详情里点「设为$label」');
    await _openSearch();
  }

  /// 长按家/公司：清除或重新设置。
  Future<void> _manageHomeWork({required bool isHome}) async {
    final poi = isHome ? _places.home : _places.work;
    final label = isHome ? '家' : '公司';
    if (poi == null) {
      await _openHomeWork(isHome: isHome);
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label：${poi.name}'),
        content: Text(poi.address),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('clear'),
            child: const Text('清除'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('reset'),
            child: const Text('重新设置'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'clear') {
      if (isHome) {
        await _places.setHome(null);
      } else {
        await _places.setWork(null);
      }
      _snack('已清除$label');
    } else if (action == 'reset') {
      await _openSearch();
    }
  }

  Future<void> _openSaved({bool offline = false}) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => SavedScreen(places: _places, initialOffline: offline),
      ),
    );
    if (!mounted) return;
    if (result is Poi) {
      _selectPoi(result);
    } else if (result is OfflineRoute) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              OfflineRouteScreen(route: result, settings: _settings),
        ),
      );
    }
  }

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        return Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 900) return _buildWide(context);
              return _buildMobile(context);
            },
          ),
        );
      },
    );
  }

  Widget _map() {
    return AppMap(
      settings: _settings,
      selectedPoi: _selectedPoi,
      trafficEnabled: _trafficOn,
      handle: _mapHandle,
      myLocation: _myLocation,
      tilt: _tilt,
      onCameraSettled: _onCameraSettled,
      onUserDragged: _onUserDragged,
    );
  }

  Widget _poiPanel(ScrollController? scrollController) {
    final poi = _selectedPoi!;
    return PoiDetailPanel(
      poi: poi,
      scrollController: scrollController,
      onClose: _closePoi,
      onNavigate: () => _openRoute(poi),
      isFavorite: _places.isFavorite(poi.id),
      onToggleFavorite: () async {
        final now = await _places.toggleFavorite(poi);
        _snack(now ? '已收藏' : '已取消收藏');
      },
      onSetAsHome: () async {
        await _places.setHome(poi);
        _snack('已把「${poi.name}」设为家');
      },
      onSetAsWork: () async {
        await _places.setWork(poi);
        _snack('已把「${poi.name}」设为公司');
      },
    );
  }

  // ---------- 窄屏 ----------

  Widget _buildMobile(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: _map()),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _searchBar(context),
                const SizedBox(height: 8),
                _providerChip(context),
              ],
            ),
          ),
        ),
        Positioned(
          right: 14,
          top: 190,
          child: _mapControls(context),
        ),
        if (!_settings.hasAnyKey)
          Positioned(
            left: 16,
            right: 16,
            bottom: 150,
            child: _guideCard(context),
          ),
        DraggableScrollableSheet(
          controller: _sheetController,
          initialChildSize: 0.16,
          minChildSize: 0.12,
          maxChildSize: 0.88,
          snap: true,
          snapSizes: const [0.16, 0.48, 0.88],
          builder: (context, scrollController) {
            return Material(
              elevation: 8,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                children: [
                  const _SheetHandle(),
                  Expanded(
                    child: _selectedPoi != null
                        ? _poiPanel(scrollController)
                        : _homeSheetContent(context, scrollController),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ---------- 宽屏（>=900）：左栏 + 右地图 ----------

  Widget _buildWide(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 380,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _searchBar(context),
                    const SizedBox(height: 10),
                    _providerChip(context),
                    const SizedBox(height: 12),
                    if (!_settings.hasAnyKey) _guideCard(context),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _selectedPoi != null
                          ? _poiPanel(null)
                          : _homeSheetContent(context, null),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _map()),
              Positioned(right: 14, top: 90, child: _mapControls(context)),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- 共用组件 ----------

  Widget _searchBar(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(28),
      color: Theme.of(context).colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: _openSearch,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(Icons.search,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '搜索地点 / 地址',
                  style: TextStyle(fontSize: 15, color: Colors.grey),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.mic_none),
                tooltip: '语音搜索（占位）',
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: '设置',
                onPressed: _openSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _providerChip(BuildContext context) {
    final sample = widget.services.isSampleFor(_settings.provider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InputChip(
          avatar: const Icon(Icons.dataset_outlined, size: 16),
          label: Text('${_settings.provider.displayName} ▾'),
          onPressed: () => _cycleProvider(context),
        ),
        if (sample) ...[
          const SizedBox(width: 8),
          const Chip(
            avatar: Icon(Icons.science_outlined, size: 16),
            label: Text('示例数据'),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );
  }

  Future<void> _cycleProvider(BuildContext context) async {
    final picked = await showModalBottomSheet<MapProvider>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('切换数据源（搜索 / 算路）')),
            for (final p in MapProvider.values)
              ListTile(
                leading: Icon(
                  p == _settings.provider
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(p.displayName),
                subtitle: Text(_settings.hasKeyFor(p) ? 'Key 已填写' : 'Key 未填写'),
                onTap: () => Navigator.of(context).pop(p),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await _settings.setProvider(picked);
  }

  Widget _mapControls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget btn(IconData icon, String tip, VoidCallback onTap,
        {bool active = false}) {
      return Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(12),
        color: scheme.surface,
        child: IconButton(
          icon: Icon(icon, color: active ? scheme.primary : null),
          tooltip: tip,
          onPressed: onTap,
        ),
      );
    }

    final following = _followLock.following;
    return Column(
      children: [
        btn(Icons.layers_outlined, '实时路况', () {
          setState(() => _trafficOn = !_trafficOn);
          _snack('实时路况${_trafficOn ? '已开' : '已关'}');
        }, active: _trafficOn),
        const SizedBox(height: 8),
        btn(Icons.add, '放大', () => _mapHandle.zoomIn()),
        const SizedBox(height: 8),
        btn(Icons.remove, '缩小', () => _mapHandle.zoomOut()),
        const SizedBox(height: 8),
        // 定位按钮：跟随锁定 = 主色实心；已定位未锁定 = 主色图标；未定位 = 普通。
        Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(12),
          color: following ? scheme.primary : scheme.surface,
          child: IconButton(
            icon: _locating
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: following ? scheme.onPrimary : scheme.primary,
                    ),
                  )
                : Icon(
                    following
                        ? Icons.my_location
                        : _myLocation != null
                            ? Icons.gps_fixed
                            : Icons.location_searching,
                    color: following
                        ? scheme.onPrimary
                        : _myLocation != null
                            ? scheme.primary
                            : null,
                  ),
            tooltip: following ? '正在跟随我的位置' : '回到我的位置',
            onPressed: _onLocate,
          ),
        ),
        const SizedBox(height: 8),
        // 2D / 3D 切换：到 3D 时显示「2D」表示可切回，态用主色区分。
        Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(12),
          color: _is3d ? scheme.primary : scheme.surface,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _toggle3d,
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: Text(
                _is3d ? '3D' : '2D',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: _is3d ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _guideCard(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('还没有填写任何 Key',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text('填入 Web Key 即可开始搜索与算路，Key 由你自己申请、只存在本机。'),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _openSettings,
              child: const Text('去设置 →'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _homeSheetContent(BuildContext context, ScrollController? controller) {
    // 示例数据（sample data）：原型占位地名，非真实记录。
    const recents = SampleMapDataService.samplePois;
    Widget shortcut(
      IconData icon,
      String label,
      VoidCallback onTap, {
      VoidCallback? onLongPress,
      bool filled = false,
    }) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FilledButton.tonal(
            onPressed: onTap,
            onLongPress: onLongPress,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: filled ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Row(
          children: [
            shortcut(
              _places.home != null ? Icons.home : Icons.home_outlined,
              '家',
              () => _openHomeWork(isHome: true),
              onLongPress: () => _manageHomeWork(isHome: true),
              filled: _places.home != null,
            ),
            shortcut(
              _places.work != null ? Icons.work : Icons.work_outlined,
              '公司',
              () => _openHomeWork(isHome: false),
              onLongPress: () => _manageHomeWork(isHome: false),
              filled: _places.work != null,
            ),
            shortcut(
              _places.favorites.isNotEmpty ? Icons.star : Icons.star_border,
              '收藏',
              () => _openSaved(),
              filled: _places.favorites.isNotEmpty,
            ),
            shortcut(
              Icons.alt_route,
              '离线路线',
              () => _openSaved(offline: true),
              filled: _places.offlineRoutes.isNotEmpty,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '长按「家 / 公司」可清除或重新设置；离线路线只含路线数据，底图需联网',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 10),
        Text('最近', style: Theme.of(context).textTheme.titleSmall),
        for (final poi in recents.take(3))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: Text(poi.name),
            subtitle: Text(poi.distanceMeters == null
                ? poi.address
                : '${poi.address} · ${formatDistance(poi.distanceMeters!)}'),
            onTap: () => setState(() => _selectedPoi = poi),
          ),
      ],
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: 40,
        height: 4.5,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
