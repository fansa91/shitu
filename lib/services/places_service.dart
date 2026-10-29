import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/offline_route.dart';
import '../models/poi.dart';

/// 常用地点与离线路线：家 / 公司 / 收藏 / 已保存路线。
///
/// 与 SettingsService 分工：这里只管「地点类」用户数据，
/// 全部以 JSON 存 SharedPreferences（结构见各模型的 toJson）。
class PlacesService extends ChangeNotifier {
  static const _kHome = 'places_home';
  static const _kWork = 'places_work';
  static const _kFavorites = 'places_favorites';
  static const _kOfflineRoutes = 'places_offline_routes';

  Poi? _home;
  Poi? _work;
  List<Poi> _favorites = [];
  List<OfflineRoute> _offlineRoutes = [];

  Poi? get home => _home;
  Poi? get work => _work;
  List<Poi> get favorites => List.unmodifiable(_favorites);
  List<OfflineRoute> get offlineRoutes => List.unmodifiable(_offlineRoutes);

  bool isFavorite(String poiId) => _favorites.any((p) => p.id == poiId);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _home = _decodePoi(prefs.getString(_kHome));
    _work = _decodePoi(prefs.getString(_kWork));
    _favorites = _decodeList(prefs.getString(_kFavorites), Poi.fromJson);
    _offlineRoutes =
        _decodeList(prefs.getString(_kOfflineRoutes), OfflineRoute.fromJson);
    notifyListeners();
  }

  Future<void> setHome(Poi? poi) async {
    _home = poi;
    notifyListeners();
    await _savePoi(_kHome, poi);
  }

  Future<void> setWork(Poi? poi) async {
    _work = poi;
    notifyListeners();
    await _savePoi(_kWork, poi);
  }

  /// 切换收藏状态，返回切换后的状态（true = 已收藏）。
  Future<bool> toggleFavorite(Poi poi) async {
    if (isFavorite(poi.id)) {
      _favorites = _favorites.where((p) => p.id != poi.id).toList();
      notifyListeners();
      await _saveFavorites();
      return false;
    }
    _favorites = [poi, ..._favorites];
    notifyListeners();
    await _saveFavorites();
    return true;
  }

  Future<void> removeFavorite(String poiId) async {
    _favorites = _favorites.where((p) => p.id != poiId).toList();
    notifyListeners();
    await _saveFavorites();
  }

  Future<void> saveOfflineRoute(OfflineRoute route) async {
    _offlineRoutes = [
      route,
      ..._offlineRoutes.where((r) => r.id != route.id),
    ];
    notifyListeners();
    await _saveOfflineRoutes();
  }

  Future<void> removeOfflineRoute(String id) async {
    _offlineRoutes = _offlineRoutes.where((r) => r.id != id).toList();
    notifyListeners();
    await _saveOfflineRoutes();
  }

  // ---------- 持久化 ----------

  Poi? _decodePoi(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return Poi.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // 存量数据损坏时不崩溃，视为未设置
    }
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

  Future<void> _savePoi(String key, Poi? poi) async {
    final prefs = await SharedPreferences.getInstance();
    if (poi == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(poi.toJson()));
    }
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kFavorites,
      jsonEncode([for (final p in _favorites) p.toJson()]),
    );
  }

  Future<void> _saveOfflineRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kOfflineRoutes,
      jsonEncode([for (final r in _offlineRoutes) r.toJson()]),
    );
  }
}
