import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/geo_point.dart';
import '../models/map_provider.dart';
import '../models/offline_route.dart';
import '../models/poi.dart';
import '../models/route_plan.dart';
import '../services/api_exception.dart';
import '../services/history_service.dart';
import '../services/location_service.dart';
import '../services/map_data_services.dart';
import '../services/places_service.dart';
import '../services/settings_service.dart';
import '../services/track_service.dart';
import '../utils/format.dart';
import '../utils/share_text.dart';
import '../widgets/app_map.dart';
import 'navigation_screen.dart';

/// 路线规划页：起终点（Poi 驱动）+ 出行方式切换 + 双路线同显 + 多方案卡。
///
/// 起点默认取设备 GPS 位置（坐标直接算路，逆地理补地名）；
/// 也可切换为文本输入，文本修改后先走当前服务商搜索取首个结果的坐标再算路；
/// 宽度 >=900 时左栏放操作区、右栏放地图。
class RouteScreen extends StatefulWidget {
  const RouteScreen({
    super.key,
    required this.destination,
    required this.settings,
    required this.services,
    required this.places,
    required this.tracks,
    required this.history,
    this.initialOrigin,
  });

  final Poi destination;
  final SettingsService settings;
  final MapDataServices services;
  final PlacesService places;
  final TrackService tracks;
  final HistoryService history;

  /// 从历史路线进入时带入的起点；为 null 时默认 GPS 起点流程。
  final Poi? initialOrigin;


  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  static const _gpsPoiId = 'gps-my-location';
  static const _myLocationPoi = Poi(
    id: _gpsPoiId,
    name: '我的位置',
    address: '',
    category: '我的位置',
  );

  final _originController = TextEditingController();
  final _locationService = LocationService();
  late Poi _originPoi = _myLocationPoi;
  late Poi _destPoi = widget.destination;

  /// 起点是否处于文本输入模式（false = 用已解析的 Poi，含 GPS 起点）。
  bool _originUseText = false;

  /// 正在取 GPS 位置（进页自动尝试 / 手动点定位按钮）。
  bool _gpsBusy = true;

  TransportMode _mode = TransportMode.driving;
  late MapProvider _routeProvider = widget.settings.provider;
  Future<RoutePlan>? _planFuture;
  RoutePlan? _plan;
  RouteOption? _selected;

  bool get _originIsGps => _originPoi.id == _gpsPoiId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialOrigin;
    if (initial != null && initial.location != null) {
      _originPoi = initial;
      _originUseText = false;
      _gpsBusy = false;
      _reload();
    } else {
      _initGpsOrigin();
    }
  }

  @override
  void dispose() {
    _originController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 进页先尝试以 GPS 位置为起点（成功直接算路，失败转文本输入模式）。
  Future<void> _initGpsOrigin() async {
    final poi = await _resolveGpsPoi(showError: false);
    if (!mounted) return;
    setState(() {
      _gpsBusy = false;
      if (poi != null) {
        _originPoi = poi;
        _originUseText = false;
      } else {
        _originUseText = true;
      }
    });
    _reload();
  }

  /// 取设备位置并组装成「我的位置」Poi：坐标走 GPS（已转 GCJ-02），
  /// 地名用当前数据源逆地理编码补；无 Key / 失败时地址留空，
  /// UI 显示「我的位置（定位坐标）」。失败返回 null。
  Future<Poi?> _resolveGpsPoi({required bool showError}) async {
    try {
      final point = await _locationService.currentLocation();
      final address = await widget.services
          .serviceFor(_routeProvider)
          .reverseGeocode(point, _routeProvider);
      return Poi(
        id: _gpsPoiId,
        name: '我的位置',
        address: address ?? '',
        category: '我的位置',
        location: point,
      );
    } on LocationException catch (e) {
      if (showError && mounted) _snack(e.message);
      return null;
    }
  }

  Future<void> _useGpsOrigin() async {
    setState(() => _gpsBusy = true);
    final poi = await _resolveGpsPoi(showError: true);
    if (!mounted) return;
    setState(() {
      _gpsBusy = false;
      if (poi != null) {
        _originPoi = poi;
        _originUseText = false;
      }
    });
    if (poi != null) _reload();
  }

  Future<void> _useGpsDestination() async {
    setState(() => _gpsBusy = true);
    final poi = await _resolveGpsPoi(showError: true);
    if (!mounted) return;
    setState(() {
      _gpsBusy = false;
      if (poi != null) _destPoi = poi;
    });
    if (poi != null) _reload();
  }

  /// 起点解析：已解析的 Poi（含 GPS 起点）有坐标且文本未被改动时，
  /// 直接用其坐标算路，不再走文本搜索；文本被改动时才搜索取首个结果。
  Future<Poi> _resolveOrigin() async {
    final text = _originController.text.trim();
    if (text.isEmpty || text == _originPoi.name) {
      if (_originPoi.location == null) {
        throw const MapApiException(
          MapApiErrorKind.precondition,
          '起点还没有坐标：点定位按钮用「我的位置」，或输入具体地点后回车',
        );
      }
      return _originPoi;
    }
    final results = await widget.services
        .serviceFor(_routeProvider)
        .searchSuggestions(text, _routeProvider);
    if (results.isEmpty) {
      throw MapApiException(
        MapApiErrorKind.precondition,
        '未找到起点「$text」，请换个名称重试',
      );
    }
    _originPoi = results.first;
    return _originPoi;
  }

  void _reload() {
    final future = _loadPlan();
    _planFuture = future;
    future.then((plan) {
      // 算路成功记一条路线历史（去重滚动，见 HistoryService）。
      widget.history.addRoute(
        originName: _originPoi.name,
        destinationName: _destPoi.name,
        mode: _mode,
        provider: _routeProvider,
        originPoint: _originPoi.location,
        destinationPoint: _destPoi.location,
      );
      if (mounted) {
        setState(() {
          _plan = plan;
          _selected =
              plan.options.where((o) => o.recommended).firstOrNull ??
                  plan.options.firstOrNull;
          // 起点已解析出坐标后回落到 Poi 展示模式（含 GPS 起点）。
          if (_originPoi.location != null) _originUseText = false;
        });
      }
    }).onError((_, _) {
      // 错误由 FutureBuilder 的错误区呈现，这里只吞掉未处理异常。
    });
  }

  Future<RoutePlan> _loadPlan() async {
    final origin = await _resolveOrigin();
    return widget.services.serviceFor(_routeProvider).planRoute(
          origin: origin,
          destination: _destPoi,
          mode: _mode,
          provider: _routeProvider,
        );
  }

  void _swap() {
    setState(() {
      final tmpPoi = _originPoi;
      _originPoi = _destPoi;
      _destPoi = tmpPoi;
      _originController.text = _originPoi.name;
      _originUseText = _originPoi.location == null;
    });
    _reload();
  }

  /// 把当前选中方案保存为离线路线（仅路线数据，底图不保存）。
  Future<void> _saveOffline() async {
    final option = _selected;
    if (option == null) return;
    final route = OfflineRoute(
      id: 'route-${DateTime.now().millisecondsSinceEpoch}',
      originName: _originPoi.name,
      destinationName: _destPoi.name,
      mode: _mode,
      provider: _routeProvider,
      durationSeconds: option.durationSeconds,
      distanceMeters: option.distanceMeters,
      strategyTags: option.strategyTags,
      points: option.points,
      steps: option.steps,
      savedAtMs: DateTime.now().millisecondsSinceEpoch,
      originPoint: _originPoi.location,
      destinationPoint: _destPoi.location,
    );
    await widget.places.saveOfflineRoute(route);
    if (mounted) _snack('已保存到「离线路线」（仅含路线数据，底图需联网）');
  }

  void _startNavigation({required bool simulated}) {
    final option = _selected;
    if (option == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NavigationScreen(
          option: option,
          originName: _originPoi.name,
          destinationName: _destPoi.name,
          destination: _destPoi,
          mode: _mode,
          provider: _routeProvider,
          settings: widget.settings,
          services: widget.services,
          tracks: widget.tracks,
          simulated: simulated,
        ),
      ),
    );
  }

  List<GeoPoint> get _selectedPoints => _selected?.points ?? const [];
  List<GeoPoint> get _alternativePoints {
    final plan = _plan;
    if (plan == null) return const [];
    for (final o in plan.options) {
      if (o != _selected && o.points.isNotEmpty) return o.points;
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('路线规划')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return Row(
              children: [
                SizedBox(
                  width: 380,
                  child: _controlPanel(context, scrollable: true),
                ),
                Expanded(child: _mapArea()),
              ],
            );
          }
          return Stack(
            children: [
              Positioned.fill(child: _mapArea()),
              Positioned(
                left: 12,
                right: 12,
                top: 10,
                child: _originDestinationCard(context),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _bottomPanel(context),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _mapArea() {
    return AppMap(
      settings: widget.settings,
      selectedRoutePoints: _selectedPoints,
      alternativeRoutePoints: _alternativePoints,
    );
  }

  Widget _controlPanel(BuildContext context, {required bool scrollable}) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _originDestinationCard(context),
        const SizedBox(height: 10),
        _schemeArea(context),
        const SizedBox(height: 10),
        _ctaRow(context),
        _saveOfflineRow(context),
      ],
    );
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: scrollable
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(14), child: content)
          : Padding(padding: const EdgeInsets.all(14), child: content),
    );
  }

  Widget _bottomPanel(BuildContext context) {
    return Material(
      elevation: 10,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _schemeArea(context),
            const SizedBox(height: 10),
            _ctaRow(context),
            _saveOfflineRow(context),
          ],
        ),
      ),
    );
  }

  /// 起点行标题文案：GPS 起点无逆地理地址时如实显示「我的位置（定位坐标）」。
  String get _originTitle {
    if (_originIsGps && _originPoi.address.isEmpty) return '我的位置（定位坐标）';
    return _originPoi.name;
  }

  Widget _originDestinationCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 3,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.circle, size: 10, color: Color(0xFF34A853)),
                const SizedBox(width: 10),
                Expanded(
                  child: _originUseText
                      ? TextField(
                          controller: _originController,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: '输入起点（回车搜索解析）',
                          ),
                          style: theme.textTheme.bodyLarge,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => setState(_reload),
                        )
                      : InkWell(
                          onTap: () {
                            setState(() {
                              _originUseText = true;
                              _originController.text = _originIsGps
                                  ? ''
                                  : _originPoi.name;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (_originIsGps) ...[
                                      Icon(Icons.my_location,
                                          size: 16,
                                          color: theme.colorScheme.primary),
                                      const SizedBox(width: 4),
                                    ],
                                    Expanded(
                                      child: Text(
                                        _originTitle,
                                        style: theme.textTheme.bodyLarge,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_originPoi.address.isNotEmpty)
                                  Text(
                                    _originPoi.address,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ),
                ),
                if (_gpsBusy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                else if (_originUseText)
                  IconButton(
                    icon: const Icon(Icons.my_location),
                    tooltip: '用我的位置作起点',
                    onPressed: _useGpsOrigin,
                  ),
                IconButton(
                  icon: const Icon(Icons.swap_vert),
                  tooltip: '交换起终点',
                  onPressed: _swap,
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.square, size: 9, color: Color(0xFFE8453C)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _destPoi.id == _gpsPoiId &&
                                _destPoi.address.isEmpty
                            ? '我的位置（定位坐标）'
                            : _destPoi.name,
                        style: theme.textTheme.bodyLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_destPoi.address.isNotEmpty)
                        Text(
                          _destPoi.address,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.my_location),
                  tooltip: '用我的位置作终点',
                  onPressed: _useGpsDestination,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '重新规划',
                  onPressed: () => setState(_reload),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<TransportMode>(
              showSelectedIcon: false,
              segments: [
                for (final m in TransportMode.values)
                  ButtonSegment(value: m, label: Text(m.displayName)),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) {
                setState(() => _mode = selection.first);
                _reload();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _schemeArea(BuildContext context) {
    final sample = widget.services.isSampleFor(_routeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('数据源', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 8),
            ...MapProvider.values.map((p) {
              final short = p.displayName.replaceAll('地图', '');
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(short),
                  selected: _routeProvider == p,
                  onSelected: (_) {
                    setState(() => _routeProvider = p);
                    _reload();
                  },
                ),
              );
            }),
            if (sample)
              const Chip(
                avatar: Icon(Icons.science_outlined, size: 16),
                label: Text('示例数据'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<RoutePlan>(
          future: _planFuture,
          builder: (context, snapshot) {
            if (_planFuture == null) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                    SizedBox(width: 10),
                    Text('正在定位起点…'),
                  ],
                ),
              );
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              final message = error is MapApiException
                  ? error.message
                  : '算路失败，请稍后重试';
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(message)),
                    TextButton(
                      onPressed: () => setState(_reload),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final plan = snapshot.data!;
            return Column(
              children: [
                for (final option in plan.options)
                  _optionCard(context, option),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _optionCard(BuildContext context, RouteOption option) {
    final selected = _selected == option;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? theme.colorScheme.primary : theme.dividerColor,
          width: selected ? 1.8 : 1,
        ),
      ),
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _selected = option),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatDuration(option.durationSeconds)} · '
                      '${formatDistance(option.distanceMeters)}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        ...option.strategyTags,
                        if (option.trafficLights > 0)
                          '红绿灯 ${option.trafficLights} 个',
                        option.tollYuan > 0
                            ? '过路费 ¥${option.tollYuan}'
                            : '无过路费',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (option.recommended)
                Chip(
                  label: const Text('推荐'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: theme.colorScheme.primary,
                  labelStyle: TextStyle(color: theme.colorScheme.onPrimary),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _saveOfflineRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          icon: const Icon(Icons.share_outlined, size: 18),
          label: const Text('分享路线'),
          onPressed: _selected == null ? null : _shareSelected,
        ),
        TextButton.icon(
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('保存离线路线'),
          onPressed: _selected == null ? null : _saveOffline,
        ),
      ],
    );
  }

  void _shareSelected() {
    final option = _selected;
    if (option == null) return;
    SharePlus.instance.share(ShareParams(
      text: routeShareText(
        originName: _originPoi.name,
        destination: _destPoi,
        mode: _mode,
        provider: _routeProvider,
        option: option,
      ),
    ));
  }

  Widget _ctaRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            icon: const Icon(Icons.navigation_outlined),
            label: const Text('开始导航'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed:
                _selected == null ? null : () => _startNavigation(simulated: false),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
          ),
          onPressed:
              _selected == null ? null : () => _startNavigation(simulated: true),
          child: const Text('模拟'),
        ),
      ],
    );
  }
}
