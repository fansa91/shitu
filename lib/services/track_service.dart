import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/nav_track.dart';

/// 已保存导航轨迹的本地存储（SharedPreferences JSON，风格同 PlacesService）。
class TrackService extends ChangeNotifier {
  static const _kTracks = 'nav_tracks';

  List<NavTrack> _tracks = [];

  List<NavTrack> get tracks => List.unmodifiable(_tracks);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kTracks);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _tracks = [
          for (final item in list.whereType<Map<String, dynamic>>())
            NavTrack.fromJson(item),
        ];
      } catch (_) {
        _tracks = []; // 存量数据损坏时不崩溃
      }
    }
    notifyListeners();
  }

  Future<void> save(NavTrack track) async {
    _tracks = [track, ..._tracks.where((t) => t.id != track.id)];
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String id) async {
    _tracks = _tracks.where((t) => t.id != id).toList();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kTracks,
      jsonEncode([for (final t in _tracks) t.toJson()]),
    );
  }
}
