import 'package:flutter/material.dart';

import '../models/map_provider.dart';
import '../models/poi.dart';
import '../services/amap_sdk_service.dart';
import '../services/map_data_service.dart';
import '../services/map_data_services.dart';
import '../services/settings_service.dart';
import '../utils/format.dart';
import '../widgets/app_map.dart';
import '../widgets/poi_detail_panel.dart';
import 'route_screen.dart';
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
  });

  final SettingsService settings;
  final MapDataServices services;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _sheetController = DraggableScrollableController();
  Poi? _selectedPoi;
  bool _trafficOn = true;
  bool _privacyPromptShown = false;

  SettingsService get _settings => widget.settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _initAmapWithPrivacy());
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
    _sheetController.dispose();
    super.dispose();
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
    if (poi != null && mounted) {
      setState(() => _selectedPoi = poi);
      if (_sheetController.isAttached) {
        _sheetController.animateTo(
          0.48,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
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

  // ---------- 窄屏 ----------

  Widget _buildMobile(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: AppMap(
            settings: _settings,
            selectedPoi: _selectedPoi,
            trafficEnabled: _trafficOn,
          ),
        ),
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
                        ? PoiDetailPanel(
                            poi: _selectedPoi!,
                            scrollController: scrollController,
                            onClose: _closePoi,
                            onNavigate: () => _openRoute(_selectedPoi!),
                          )
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
                          ? PoiDetailPanel(
                              poi: _selectedPoi!,
                              onClose: _closePoi,
                              onNavigate: () => _openRoute(_selectedPoi!),
                            )
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
              Positioned.fill(
                child: AppMap(
                  settings: _settings,
                  selectedPoi: _selectedPoi,
                  trafficEnabled: _trafficOn,
                ),
              ),
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

    return Column(
      children: [
        btn(Icons.layers_outlined, '图层', () {
          setState(() => _trafficOn = !_trafficOn);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('实时路况${_trafficOn ? '已开' : '已关'}（骨架占位）')),
          );
        }, active: _trafficOn),
        const SizedBox(height: 8),
        btn(Icons.add, '放大', () {}),
        const SizedBox(height: 8),
        btn(Icons.remove, '缩小', () {}),
        const SizedBox(height: 8),
        btn(Icons.my_location, '回到我的位置', () {}),
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
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Row(
          children: [
            for (final (icon, label) in [
              (Icons.home_outlined, '家'),
              (Icons.work_outlined, '公司'),
              (Icons.star_border, '收藏'),
              (Icons.download_outlined, '离线'),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilledButton.tonal(
                    onPressed: () {},
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 20),
                        const SizedBox(height: 2),
                        Text(label, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
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
