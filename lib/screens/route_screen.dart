import 'package:flutter/material.dart';

import '../models/map_provider.dart';
import '../models/poi.dart';
import '../models/route_plan.dart';
import '../services/map_data_service.dart';
import '../services/settings_service.dart';
import '../utils/format.dart';
import '../widgets/fake_map.dart';
import 'navigation_screen.dart';

/// 路线规划页：起终点卡 + 出行方式切换 + 双路线同显 + 多方案卡。
/// 宽度 >=900 时左栏放操作区、右栏放地图。
class RouteScreen extends StatefulWidget {
  const RouteScreen({
    super.key,
    required this.destination,
    required this.settings,
    required this.mapData,
  });

  final Poi destination;
  final SettingsService settings;
  final MapDataService mapData;

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  static const _myLocation = '我的位置';
  late String _originName = _myLocation;
  late String _destinationName = widget.destination.name;
  TransportMode _mode = TransportMode.driving;
  late MapProvider _routeProvider = widget.settings.provider;
  late Future<RoutePlan> _planFuture;
  RouteOption? _selected;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _planFuture = widget.mapData.planRoute(
      originName: _originName,
      destination: widget.destination,
      mode: _mode,
      provider: _routeProvider,
    );
    _planFuture.then((plan) {
      if (mounted) {
        setState(() => _selected =
            plan.options.where((o) => o.recommended).firstOrNull ??
                plan.options.firstOrNull);
      }
    });
  }

  void _swap() {
    setState(() {
      final tmp = _originName;
      _originName = _destinationName;
      _destinationName = tmp;
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
          destinationName: _destinationName,
          settings: widget.settings,
          simulated: simulated,
        ),
      ),
    );
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
                const Expanded(child: FakeMap(showRoute: true)),
              ],
            );
          }
          return Stack(
            children: [
              const Positioned.fill(child: FakeMap(showRoute: true)),
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
                  child: Text(
                    _originName,
                    style: theme.textTheme.bodyLarge,
                    overflow: TextOverflow.ellipsis,
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
                    _destinationName,
                    style: theme.textTheme.bodyLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 48),
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
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<RoutePlan>(
          future: _planFuture,
          builder: (context, snapshot) {
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
