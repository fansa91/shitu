import 'package:flutter/material.dart';

import '../models/nav_track.dart';
import '../models/offline_route.dart';
import '../models/poi.dart';
import '../services/places_service.dart';
import '../services/track_service.dart';
import '../utils/format.dart';

/// 「收藏 / 离线路线 / 轨迹」列表页（主页快捷入口打开）。
///
/// 点收藏条目 → 以该 [Poi] 关闭本页回主页（主页负责移图开面板）；
/// 点离线路线 → 以该 [OfflineRoute] 关闭本页（主页负责打开详情页）；
/// 点轨迹 → 以该 [NavTrack] 关闭本页（主页负责打开回放页）。
class SavedScreen extends StatefulWidget {
  const SavedScreen({
    super.key,
    required this.places,
    required this.tracks,
    this.initialOffline = false,
  });

  final PlacesService places;
  final TrackService tracks;

  /// true 时默认停在「离线路线」页签。
  final bool initialOffline;

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialOffline ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏与离线路线'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.star_border), text: '收藏'),
            Tab(icon: Icon(Icons.alt_route), text: '离线路线'),
            Tab(icon: Icon(Icons.route_outlined), text: '轨迹'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.places, widget.tracks]),
        builder: (context, _) => TabBarView(
          controller: _tabs,
          children: [
            _favoritesTab(context),
            _offlineTab(context),
            _tracksTab(context),
          ],
        ),
      ),
    );
  }

  Widget _favoritesTab(BuildContext context) {
    final favorites = widget.places.favorites;
    if (favorites.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('还没有收藏的地点。\n在地点详情里点「收藏」就会出现在这里。',
              textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.builder(
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final poi = favorites[index];
        return Dismissible(
          key: ValueKey('fav-${poi.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Theme.of(context).colorScheme.errorContainer,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete_outline),
          ),
          onDismissed: (_) => widget.places.removeFavorite(poi.id),
          child: ListTile(
            leading: const Icon(Icons.star, color: Colors.amber),
            title: Text(poi.name),
            subtitle: Text(poi.address, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: () => widget.places.removeFavorite(poi.id),
            ),
            onTap: () => Navigator.of(context).pop<Poi>(poi),
          ),
        );
      },
    );
  }

  Widget _offlineTab(BuildContext context) {
    final routes = widget.places.offlineRoutes;
    if (routes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '还没有保存的离线路线。\n在路线规划页选中方案后点「保存离线路线」。\n'
            '说明：离线路线只保存路线数据，地图底图仍需联网。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: routes.length,
      itemBuilder: (context, index) {
        final route = routes[index];
        return ListTile(
          leading: const Icon(Icons.alt_route),
          title: Text('${route.originName} → ${route.destinationName}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${route.mode.displayName} · ${formatDuration(route.durationSeconds)} · '
            '${formatDistance(route.distanceMeters)} · '
            '${route.savedAt.month}月${route.savedAt.day}日保存',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
            onPressed: () => widget.places.removeOfflineRoute(route.id),
          ),
          onTap: () => Navigator.of(context).pop<OfflineRoute>(route),
        );
      },
    );
  }

  Widget _tracksTab(BuildContext context) {
    final tracks = widget.tracks.tracks;
    if (tracks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '还没有保存的轨迹。\n导航到达或结束时点「保存轨迹」就会出现在这里。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final started =
            DateTime.fromMillisecondsSinceEpoch(track.startedAtMs);
        return ListTile(
          leading: const Icon(Icons.route_outlined),
          title: Text(track.name,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${formatDistance(track.distanceMeters)} · '
            '${formatDuration(track.durationSeconds)} · '
            '${started.month}月${started.day}日 ${formatClock(started)}',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
            onPressed: () => widget.tracks.remove(track.id),
          ),
          onTap: () => Navigator.of(context).pop<NavTrack>(track),
        );
      },
    );
  }
}
