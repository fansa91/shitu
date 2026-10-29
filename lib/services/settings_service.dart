import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/map_provider.dart';
import '../theme/appearance.dart';

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
  static const _kAmapSdkAndroidKey = 'amap_sdk_android_key';
  static const _kAmapSdkIosKey = 'amap_sdk_ios_key';
  static const _kPrivacyAgreed = 'privacy_agreed';
  static const _kThemeMode = 'theme_mode';
  static const _kDynamicColor = 'dynamic_color_enabled';
  static const _kSeedColorValue = 'seed_color_value';

  MapProvider _provider = MapProvider.amap;
  String _amapSdkAndroidKey = '';
  String _amapSdkIosKey = '';
  bool _privacyAgreed = false;
  final Map<MapProvider, String> _keys = {
    for (final p in MapProvider.values) p: '',
  };
  String _nvidiaKey = '';
  TtsEngine _ttsEngine = TtsEngine.system;
  bool _ttsPresynthesize = true;
  AppThemeMode _themeMode = AppThemeMode.system;
  bool _dynamicColorEnabled = true;
  int _seedColorValue = 0xFF1A73E8; // brandSeedColor 的 ARGB

  MapProvider get provider => _provider;

  /// 高德原生 SDK 的 Android Key（与 Web Key 分开申请、分开填）。
  String get amapSdkAndroidKey => _amapSdkAndroidKey;

  /// 高德原生 SDK 的 iOS Key。
  String get amapSdkIosKey => _amapSdkIosKey;

  bool get hasAmapSdkAndroidKey => _amapSdkAndroidKey.trim().isNotEmpty;
  bool get hasAmapSdkIosKey => _amapSdkIosKey.trim().isNotEmpty;

  /// 用户是否已在首启隐私对话框中同意（同意前绝不初始化地图 SDK）。
  bool get privacyAgreed => _privacyAgreed;
  TtsEngine get ttsEngine => _ttsEngine;
  bool get ttsPresynthesize => _ttsPresynthesize;
  String get nvidiaKey => _nvidiaKey;

  /// 外观：主题模式 / 是否跟随系统动态取色 / 自定义种子色。
  AppThemeMode get themeMode => _themeMode;
  bool get dynamicColorEnabled => _dynamicColorEnabled;
  Color get seedColor => Color(_seedColorValue);
  int get seedColorValue => _seedColorValue;

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
    _amapSdkAndroidKey = prefs.getString(_kAmapSdkAndroidKey) ?? '';
    _amapSdkIosKey = prefs.getString(_kAmapSdkIosKey) ?? '';
    _privacyAgreed = prefs.getBool(_kPrivacyAgreed) ?? false;
    _themeMode = _themeModeFromName(prefs.getString(_kThemeMode));
    _dynamicColorEnabled = prefs.getBool(_kDynamicColor) ?? true;
    _seedColorValue = prefs.getInt(_kSeedColorValue) ?? _seedColorValue;
    notifyListeners();
  }

  Future<void> setAmapSdkKeys({
    required String androidKey,
    required String iosKey,
  }) async {
    _amapSdkAndroidKey = androidKey.trim();
    _amapSdkIosKey = iosKey.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAmapSdkAndroidKey, _amapSdkAndroidKey);
    await prefs.setString(_kAmapSdkIosKey, _amapSdkIosKey);
  }

  Future<void> setPrivacyAgreed(bool value) async {
    _privacyAgreed = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrivacyAgreed, value);
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

  Future<void> setThemeMode(AppThemeMode value) async {
    _themeMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, value.name);
  }

  Future<void> setDynamicColorEnabled(bool value) async {
    _dynamicColorEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDynamicColor, value);
  }

  Future<void> setSeedColor(Color value) async {
    _seedColorValue = value.toARGB32();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSeedColorValue, _seedColorValue);
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

  AppThemeMode _themeModeFromName(String? name) =>
      AppThemeMode.values.where((e) => e.name == name).firstOrNull ??
      AppThemeMode.system;
}
