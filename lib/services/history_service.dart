import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/geo_point.dart';
import '../models/history_entry.dart';
import '../models/map_provider.dart';
import '../models/poi.dart';

/// 搜索历史 + 路线历史（SharedPreferences JSON）。
/// 各上限 [maxEntries] 条，按 POI id / 起终点+方式去重，新的排前面滚动淘汰。
class HistoryService extends ChangeNotifier {
  static const _kSearches = 'history_searches';
  static const _kRoutes = 'history_routes';
  static const maxEntries = 20;

  List<SearchHistoryEntry> _searches = [];
  List<RouteHistoryEntry> _routes = [];

  List<SearchHistoryEntry> get searches => List.unmodifiable(_searches);
  List<RouteHistoryEntry> get routes => List.unmodifiable(_routes);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _searches = _decodeList(
        prefs.getString(_kSearches), SearchHistoryEntry.fromJson);
    _routes =
        _decodeList(prefs.getString(_kRoutes), RouteHistoryEntry.fromJson);
    notifyListeners();
  }

  Future<void> addSearch(Poi poi, String query) async {
    final entry = SearchHistoryEntry(
      poi: poi,
      query: query.trim(),
      atMs: DateTime.now().millisecondsSinceEpoch,
    );
    _searches = [
      entry,
      ..._searches.where((e) => e.poi.id != poi.id),
    ].take(maxEntries).toList();
    notifyListeners();
    await _persistSearches();
  }

  Future<void> clearSearches() async {
    _searches = [];
    notifyListeners();
    await _persistSearches();
  }

  Future<void> addRoute({
    required String originName,
    required String destinationName,
    required TransportMode mode,
    required MapProvider provider,
    GeoPoint? originPoint,
    GeoPoint? destinationPoint,
  }) async {
    final entry = RouteHistoryEntry(
      originName: originName,
      destinationName: destinationName,
      mode: mode,
      provider: provider,
      atMs: DateTime.now().millisecondsSinceEpoch,
      originPoint: originPoint,
      destinationPoint: destinationPoint,
    );
    bool same(RouteHistoryEntry e) =>
        e.originName == originName &&
        e.destinationName == destinationName &&
        e.mode == mode;
    _routes = [entry, ..._routes.where((e) => !same(e))]
        .take(maxEntries)
        .toList();
    notifyListeners();
    await _persistRoutes();
  }

  Future<void> clearRoutes() async {
    _routes = [];
    notifyListeners();
    await _persistRoutes();
  }

  List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final item in list.whereType<Map<String, dynamic>>())
          fromJson(item),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _persistSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kSearches,
      jsonEncode([for (final e in _searches) e.toJson()]),
    );
  }

  Future<void> _persistRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kRoutes,
      jsonEncode([for (final e in _routes) e.toJson()]),
    );
  }
}
