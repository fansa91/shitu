import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/map_provider.dart';
import '../theme/appearance.dart';

/// 应用设置：三家服务商 Key、当前服务商、TTS 偏好。
///
/// 持久化分工：Key 类字段（四家 Web/SDK Key + 英伟达 Key）存
/// flutter_secure_storage（Android Keystore / iOS Keychain），不落明文；
/// 其余非敏感设置仍存 SharedPreferences。对外同步 getter 接口不变，
/// 安全存储在 [load] 里异步读完并做一次性明文迁移（见 [_loadKeys]）。
/// 安全存储不可用时（如无平台通道的测试环境）Key 仅内存生效，
/// 绝不回退写明文。
class SettingsService extends ChangeNotifier {
  SettingsService({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;
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
  static const _kNvidiaVoice = 'nvidia_voice';
  static const _kMapCompatMode = 'map_compat_mode';
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
  String _nvidiaVoice = 'Siwei';
  TtsEngine _ttsEngine = TtsEngine.system;
  bool _ttsPresynthesize = true;
  bool _mapCompatMode = false;
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

  /// 英伟达音色短名（见 tts_service.nvidiaVoiceNames），默认 Siwei。
  String get nvidiaVoice => _nvidiaVoice;

  /// 地图兼容模式：开时 AMapWidget 只用最保守渲染配置（关建筑/路况/
  /// 指南针/比例尺/标注/POI 点击），供真实地图崩溃或老设备时排查与保底。
  bool get mapCompatMode => _mapCompatMode;

  /// 外观：主题模式 / 是否跟随系统动态取色 / 自定义种子色。
  AppThemeMode get themeMode => _themeMode;
  bool get dynamicColorEnabled => _dynamicColorEnabled;
  Color get seedColor => Color(_seedColorValue);
  int get seedColorValue => _seedColorValue;

  String keyFor(MapProvider provider) => _keys[provider] ?? '';
  bool hasKeyFor(MapProvider provider) => keyFor(provider).trim().isNotEmpty;

  /// 是否至少填了一家服务商的 Key（主页引导卡以此判断）。
  bool get hasAnyKey => MapProvider.values.any(hasKeyFor);

  /// 全部 Key 类字段的存储 key（安全存储与旧 prefs 共用同一组名字）。
  static const _keyFields = [
    _kKeyAmap,
    _kKeyBaidu,
    _kKeyTencent,
    _kKeyNvidia,
    _kAmapSdkAndroidKey,
    _kAmapSdkIosKey,
  ];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _provider = _providerFromName(prefs.getString(_kProvider));
    _nvidiaVoice = prefs.getString(_kNvidiaVoice) ?? 'Siwei';
    _ttsEngine = _ttsFromName(prefs.getString(_kTtsEngine));
    _ttsPresynthesize = prefs.getBool(_kTtsPresynthesize) ?? true;
    _privacyAgreed = prefs.getBool(_kPrivacyAgreed) ?? false;
    _mapCompatMode = prefs.getBool(_kMapCompatMode) ?? false;
    _themeMode = _themeModeFromName(prefs.getString(_kThemeMode));
    _dynamicColorEnabled = prefs.getBool(_kDynamicColor) ?? true;
    _seedColorValue = prefs.getInt(_kSeedColorValue) ?? _seedColorValue;
    await _loadKeys(prefs);
    notifyListeners();
  }

  /// Key 读取 + 一次性迁移：
  /// 安全存储有值 → 用它，并清掉可能残留的旧明文；
  /// 安全存储为空而旧 prefs 有值 → 搬进安全存储并删旧明文；
  /// 安全存储整体不可用 → 用旧明文值兜底（不迁移、不删，留待下次）。
  Future<void> _loadKeys(SharedPreferences prefs) async {
    final legacy = {
      for (final k in _keyFields) k: prefs.getString(k) ?? '',
    };
    Map<String, String?>? secureValues;
    try {
      secureValues = {
        for (final k in _keyFields) k: await _secure.read(key: k),
      };
    } catch (_) {
      secureValues = null; // 安全存储不可用：走 legacy 兜底
    }
    final resolved = <String, String>{};
    for (final k in _keyFields) {
      final secureValue = secureValues?[k];
      final legacyValue = legacy[k] ?? '';
      if (secureValue != null && secureValue.isNotEmpty) {
        resolved[k] = secureValue;
        if (legacyValue.isNotEmpty) await prefs.remove(k);
      } else if (legacyValue.isNotEmpty && secureValues != null) {
        resolved[k] = legacyValue;
        try {
          await _secure.write(key: k, value: legacyValue);
          await prefs.remove(k);
        } catch (_) {
          // 迁移失败保留明文原样，下次 load 再试，不丢 Key。
        }
      } else {
        resolved[k] = legacyValue;
      }
    }
    _keys[MapProvider.amap] = resolved[_kKeyAmap] ?? '';
    _keys[MapProvider.baidu] = resolved[_kKeyBaidu] ?? '';
    _keys[MapProvider.tencent] = resolved[_kKeyTencent] ?? '';
    _nvidiaKey = resolved[_kKeyNvidia] ?? '';
    _amapSdkAndroidKey = resolved[_kAmapSdkAndroidKey] ?? '';
    _amapSdkIosKey = resolved[_kAmapSdkIosKey] ?? '';
  }

  /// 写安全存储：空值删除；失败静默（仅内存生效，绝不回退明文）。
  Future<void> _writeSecure(String storageKey, String value) async {
    try {
      if (value.isEmpty) {
        await _secure.delete(key: storageKey);
      } else {
        await _secure.write(key: storageKey, value: value);
      }
    } catch (_) {
      // 安全存储不可用时不落任何明文，Key 只在本次运行内存中有效。
    }
  }

  Future<void> setAmapSdkKeys({
    required String androidKey,
    required String iosKey,
  }) async {
    _amapSdkAndroidKey = androidKey.trim();
    _amapSdkIosKey = iosKey.trim();
    notifyListeners();
    await _writeSecure(_kAmapSdkAndroidKey, _amapSdkAndroidKey);
    await _writeSecure(_kAmapSdkIosKey, _amapSdkIosKey);
  }

  Future<void> setPrivacyAgreed(bool value) async {
    _privacyAgreed = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrivacyAgreed, value);
  }

  Future<void> setMapCompatMode(bool value) async {
    _mapCompatMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMapCompatMode, value);
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
    await _writeSecure(_storageKeyFor(provider), value.trim());
  }

  Future<void> setNvidiaVoice(String value) async {
    _nvidiaVoice = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNvidiaVoice, value);
  }

  Future<void> setNvidiaKey(String value) async {
    _nvidiaKey = value.trim();
    notifyListeners();
    await _writeSecure(_kKeyNvidia, value.trim());
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
