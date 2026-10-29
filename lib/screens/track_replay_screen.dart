import 'package:flutter/material.dart';

import '../models/nav_track.dart';
import '../services/settings_service.dart';
import '../utils/format.dart';
import '../widgets/app_map.dart';

/// 轨迹回放：地图上画出导航时记录的实际轨迹折线 + 行程统计。
/// 桌面/FakeMap 环境画示意线（AppMap 既有行为），真机高德底图画真实轨迹。
class TrackReplayScreen extends StatelessWidget {
  const TrackReplayScreen({
    super.key,
    required this.track,
    required this.settings,
  });

  final NavTrack track;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final started = DateTime.fromMillisecondsSinceEpoch(track.startedAtMs);
    return Scaffold(
      appBar: AppBar(title: const Text('轨迹回放')),
      body: Column(
        children: [
          Expanded(
            child: AppMap(
              settings: settings,
              selectedRoutePoints: track.points,
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
                      track.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '实际里程 ${formatDistance(track.distanceMeters)} · '
                      '用时 ${formatDuration(track.durationSeconds)} · '
                      '${track.points.length} 个轨迹点',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${started.year}-${started.month}-${started.day} '
                      '${formatClock(started)} 出发 · '
                      '${track.originName} → ${track.destinationName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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
