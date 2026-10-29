import 'package:flutter/material.dart';

import '../models/offline_route.dart';
import '../services/settings_service.dart';
import '../utils/format.dart';
import '../widgets/app_map.dart';

/// 离线路线详情：地图上画出保存的折线 + 摘要与分步文案。
///
/// 诚实说明：保存的只有路线数据（折线/步骤/起终点），地图底图由高德 SDK
/// 实时加载，无网络时底图区域为空白，但路线信息本身可离线查看。
class OfflineRouteScreen extends StatelessWidget {
  const OfflineRouteScreen({
    super.key,
    required this.route,
    required this.settings,
  });

  final OfflineRoute route;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('离线路线')),
      body: Column(
        children: [
          Expanded(
            child: AppMap(
              settings: settings,
              selectedRoutePoints: route.points,
              showLocationDot: false,
            ),
          ),
          Material(
            elevation: 8,
            color: theme.colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${route.originName} → ${route.destinationName}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${route.mode.displayName} · '
                      '${formatDuration(route.durationSeconds)} · '
                      '${formatDistance(route.distanceMeters)}'
                      '${route.strategyTags.isEmpty ? '' : ' · ${route.strategyTags.join(' · ')}'}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 15, color: theme.colorScheme.outline),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '离线仅含路线数据，底图需联网加载',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline),
                          ),
                        ),
                      ],
                    ),
                    if (route.steps.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: route.steps.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${i + 1}. ',
                                    style: theme.textTheme.bodySmall),
                                Expanded(
                                  child: Text(route.steps[i],
                                      style: theme.textTheme.bodySmall),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
