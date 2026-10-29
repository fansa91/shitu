import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/map_provider.dart';

/// 应用设置：三家服务商 Key、当前服务商、TTS 偏好。
///
/// TODO(安全): 骨架阶段用 SharedPreferences 明文持久化以便调试；
/// 正式版应换成 flutter_secure_storage，Key 不落明文。
class SettingsService extends ChangeNotifier {
  static const _kProvider = 'provider';
  static const _kKeyAmap = 'key_amap';
  static const _kKeyBaidu = 'key_baidu';
  static const _kKeyTencent = 'key_tencent';
  static const _kKeyNvidia = 'key_nvidia';
  static const _kTtsEngine = 'tts_engine';
  static const _kTtsPresynthesize = 'tts_presynthesize';

  MapProvider _provider = MapProvider.amap;
  final Map<MapProvider, String> _keys = {
    for (final p in MapProvider.values) p: '',
  };
  String _nvidiaKey = '';
  TtsEngine _ttsEngine = TtsEngine.system;
  bool _ttsPresynthesize = true;

  MapProvider get provider => _provider;
  TtsEngine get ttsEngine => _ttsEngine;
  bool get ttsPresynthesize => _ttsPresynthesize;
  String get nvidiaKey => _nvidiaKey;

  String keyFor(MapProvider provider) => _keys[provider] ?? '';
  bool hasKeyFor(MapProvider provider) => keyFor(provider).trim().isNotEmpty;

  /// 是否至少填了一家服务商的 Key（主页引导卡以此判断）。
  bool get hasAnyKey => MapProvider.values.any(hasKeyFor);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _provider = _providerFromName(prefs.getString(_kProvider));
    _keys[MapProvider.amap] = prefs.getString(_kKeyAmap) ?? '';
    _keys[MapProvider.baidu] = prefs.getString(_kKeyBaidu) ?? '';
    _keys[MapProvider.tencent] = prefs.getString(_kKeyTencent) ?? '';
    _nvidiaKey = prefs.getString(_kKeyNvidia) ?? '';
    _ttsEngine = _ttsFromName(prefs.getString(_kTtsEngine));
    _ttsPresynthesize = prefs.getBool(_kTtsPresynthesize) ?? true;
    notifyListeners();
  }

  Future<void> setProvider(MapProvider value) async {
    _provider = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProvider, value.name);
  }

  Future<void> setKeyFor(MapProvider provider, String value) async {
    _keys[provider] = value.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKeyFor(provider), value.trim());
  }

  Future<void> setNvidiaKey(String value) async {
    _nvidiaKey = value.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKeyNvidia, value.trim());
  }

  Future<void> setTtsEngine(TtsEngine value) async {
    _ttsEngine = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTtsEngine, value.name);
  }

  Future<void> setTtsPresynthesize(bool value) async {
    _ttsPresynthesize = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTtsPresynthesize, value);
  }

  String _storageKeyFor(MapProvider provider) => switch (provider) {
        MapProvider.amap => _kKeyAmap,
        MapProvider.baidu => _kKeyBaidu,
        MapProvider.tencent => _kKeyTencent,
      };

  MapProvider _providerFromName(String? name) =>
      MapProvider.values.where((p) => p.name == name).firstOrNull ??
      MapProvider.amap;

  TtsEngine _ttsFromName(String? name) =>
      TtsEngine.values.where((e) => e.name == name).firstOrNull ??
      TtsEngine.system;
}
