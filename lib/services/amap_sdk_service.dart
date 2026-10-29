import 'package:flutter/foundation.dart';

import 'settings_service.dart';

/// 高德原生地图 SDK 的接入状态管理（插件选型见 AmapMapView 注释：
/// 官方 amap_flutter_map 3.0.0 在 Flutter 3.47 下 CFE 编译失败，
/// 改用社区维护 fork amap_map 1.0.15）。
///
/// 该插件的初始化方式是 AMapInitializer.init(context, apiKey:) +
/// updatePrivacyAgree(...)，由 AmapMapView 在首次构建前调用；
/// 这里的 [initialize] 做前置门控与「就绪」标记：必须先有用户隐私同意、
/// 且当前平台对应的 SDK Key 已在设置里填写，Key 绝不硬编码。
class AmapSdkService {
  AmapSdkService._();

  static final AmapSdkService instance = AmapSdkService._();

  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// 真实底图只在 Android / iOS 提供；桌面/Web 一律走 FakeMap。
  bool get isMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// 当前平台对应的 SDK Key（运行时从设置读取）。
  String sdkKeyForCurrentPlatform(SettingsService settings) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return settings.amapSdkAndroidKey.trim();
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return settings.amapSdkIosKey.trim();
    }
    return '';
  }

  /// 是否满足展示真实高德地图的全部条件：
  /// 移动端 + 已隐私同意 + 已初始化 + 当前平台 SDK Key 非空。
  bool canShowRealMap(SettingsService settings) {
    return isMobilePlatform &&
        settings.privacyAgreed &&
        _initialized &&
        sdkKeyForCurrentPlatform(settings).isNotEmpty;
  }

  /// 隐私同意后调用：仅标记就绪。不同意时永远不会被调用，
  /// 地图全程回退 FakeMap。Key 变更后需重启 App 重新走此流程。
  Future<bool> initialize(SettingsService settings) async {
    if (!isMobilePlatform) return false;
    if (!settings.privacyAgreed) return false;
    if (settings.amapSdkAndroidKey.trim().isEmpty &&
        settings.amapSdkIosKey.trim().isEmpty) {
      return false;
    }
    _initialized = true;
    return true;
  }
}
