import 'package:flutter/material.dart';

import '../models/poi.dart';
import '../utils/format.dart';

/// POI 详情面板：主页底部半开面板的内容组件。
class PoiDetailPanel extends StatelessWidget {
  const PoiDetailPanel({
    super.key,
    required this.poi,
    required this.onClose,
    required this.onNavigate,
    this.scrollController,
    this.isFavorite = false,
    this.onToggleFavorite,
    this.onSetAsHome,
    this.onSetAsWork,
  });

  final Poi poi;
  final VoidCallback onClose;
  final VoidCallback onNavigate;
  final ScrollController? scrollController;

  /// 当前 POI 是否已收藏（决定收藏按钮的填充态与文案）。
  final bool isFavorite;

  /// 收藏切换；为 null 时按钮回退旧占位行为（不应发生于主页接线后）。
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onSetAsHome;
  final VoidCallback? onSetAsWork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                poi.name,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '关闭',
              onPressed: onClose,
            ),
          ],
        ),
        Text(
          poi.distanceMeters == null
              ? poi.address
              : '${poi.address} · 距你 ${formatDistance(poi.distanceMeters!)}',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (poi.businessHours != null || poi.phone != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              [
                if (poi.businessHours != null) '营业 ${poi.businessHours}',
                if (poi.phone != null) poi.phone!,
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          children: [
            Chip(
              label: Text(poi.category),
              visualDensity: VisualDensity.compact,
            ),
            for (final tag in poi.tags)
              Chip(label: Text(tag), visualDensity: VisualDensity.compact),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(isFavorite ? Icons.star : Icons.star_border,
                    color: isFavorite ? Colors.amber.shade700 : null),
                label: Text(isFavorite ? '已收藏' : '收藏'),
                onPressed: onToggleFavorite,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.share_outlined),
                label: const Text('分享'),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('分享功能骨架占位')),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.directions),
                label: const Text('去这里'),
                onPressed: onNavigate,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.home_outlined, size: 18),
                label: const Text('设为家'),
                onPressed: onSetAsHome,
              ),
            ),
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.work_outlined, size: 18),
                label: const Text('设为公司'),
                onPressed: onSetAsWork,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
