import 'package:flutter/material.dart';

import '../models/geo_point.dart';
import '../models/map_provider.dart';
import '../models/poi.dart';
import '../models/route_plan.dart';
import '../services/api_exception.dart';
import '../services/map_data_services.dart';
import '../services/settings_service.dart';
import '../utils/format.dart';
import '../widgets/app_map.dart';
import 'navigation_screen.dart';

/// 路线规划页：起终点（Poi 驱动）+ 出行方式切换 + 双路线同显 + 多方案卡。
///
/// 起点文本被修改后，先走当前服务商搜索取首个结果的坐标再算路；
/// 宽度 >=900 时左栏放操作区、右栏放地图。
class RouteScreen extends StatefulWidget {
  const RouteScreen({
    super.key,
    required this.destination,
    required this.settings,
    required this.services,
  });

  final Poi destination;
  final SettingsService settings;
  final MapDataServices services;

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  static const _myLocationPoi = Poi(
    id: 'origin-my-location',
    name: '我的位置',
    address: '',
    category: '起点',
  );

  final _originController = TextEditingController(text: '我的位置');
  late Poi _originPoi = _myLocationPoi;
  late Poi _destPoi = widget.destination;
  TransportMode _mode = TransportMode.driving;
  late MapProvider _routeProvider = widget.settings.provider;
  late Future<RoutePlan> _planFuture;
  RoutePlan? _plan;
  RouteOption? _selected;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _originController.dispose();
    super.dispose();
  }

  /// 起点文本与已解析的起点不一致时，先搜索解析坐标（取首个结果）。
  Future<Poi> _resolveOrigin() async {
    final text = _originController.text.trim();
    if (text.isEmpty || text == _originPoi.name) return _originPoi;
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
    _planFuture = _loadPlan();
    _planFuture.then((plan) {
      if (mounted) {
        setState(() {
          _plan = plan;
          _selected =
              plan.options.where((o) => o.recommended).firstOrNull ??
                  plan.options.firstOrNull;
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
    });
    _reload();
  }

  void _startNavigation({required bool simulated}) {
    final option = _selected;
    if (option == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NavigationScreen(
          option: option,
          destinationName: _destPoi.name,
          settings: widget.settings,
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
          ],
        ),
      ),
    );
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
                  child: TextField(
                    controller: _originController,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: '输入起点（回车搜索解析）',
                    ),
                    style: theme.textTheme.bodyLarge,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => setState(_reload),
                  ),
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
                  child: Text(
                    _destPoi.name,
                    style: theme.textTheme.bodyLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
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
