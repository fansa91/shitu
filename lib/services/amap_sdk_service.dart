import 'package:flutter/foundation.dart';

import 'amap_init_gate.dart';
import 'settings_service.dart';

/// 高德原生地图 SDK 的接入状态管理（插件选型见 AmapMapView 注释：
/// 官方 amap_flutter_map 3.0.0 vendoring 进仓并打补丁，见
/// packages/amap_flutter_map/VENDORED.md）。
///
/// 初始化纪律（v0.2 真机冷启动闪退后加固）：
/// - 插件注入前准备只能经 [runPluginInit] 走 [gate] 单飞：
///   同一 Key 只准备一次、失败可重试、Key 变化重新准备；
///   Key/隐私本体经 AMapWidget 创建参数在原生建图前注入（见 AmapMapView）；
/// - AmapMapView 必须等 [runPluginInit] 成功后才创建 AMapWidget，
///   失败时回落 FakeMap 并把原因留在 [lastInitError] 供横幅/诊断展示；
/// - [canShowRealMap] 只表达「意图」（移动端+已同意隐私+已填 Key），
///   不再等同于「插件已初始化成功」。
class AmapSdkService extends ChangeNotifier {
  AmapSdkService._();

  static final AmapSdkService instance = AmapSdkService._();

  final AmapInitGate gate = AmapInitGate();

  bool get isInitialized => gate.isReady;

  /// 最近一次插件初始化失败的原因（null = 未失败）。
  String? get lastInitError => gate.lastError;

  /// 「关于」页诊断文案：当前高德地图 SDK 状态一句话。
  String get diagnosticText => switch (gate.status) {
        AmapInitStatus.idle => '地图 SDK 未初始化（未填 Key 或未同意隐私）',
        AmapInitStatus.initializing => '地图 SDK 初始化中…',
        AmapInitStatus.ready => '地图 SDK 已就绪',
        AmapInitStatus.failed => '地图 SDK 初始化失败：${gate.lastError ?? '未知原因'}',
      };

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

  /// 当前双端 Key 的不敏感指纹：只用于判断「Key 是否变了」与给地图
  /// Widget 做 ValueKey，绝不含 Key 原文。
  String keyIdFor(SettingsService settings) =>
      '${settings.amapSdkAndroidKey.trim().hashCode}'
      ':${settings.amapSdkIosKey.trim().hashCode}';

  /// 是否具备展示真实高德地图的意图条件：
  /// 移动端 + 已隐私同意 + 当前平台 SDK Key 非空。
  /// （插件初始化成败由 AmapMapView 内部的门控 Future 决定，失败回落 FakeMap。）
  bool canShowRealMap(SettingsService settings) {
    return isMobilePlatform &&
        settings.privacyAgreed &&
        sdkKeyForCurrentPlatform(settings).isNotEmpty;
  }

  /// 主页隐私流程调用：条件具备时仅做状态预热/通知（真正的插件初始化
  /// 由 AmapMapView 经 [runPluginInit] 在建图前完成）。保留此入口是为了
  /// 让主页在同意隐私后立刻重建、切到真实地图路径。
  Future<bool> initialize(SettingsService settings) async {
    final ok = canShowRealMap(settings);
    notifyListeners();
    return ok;
  }

  /// 经门控执行插件注入前准备（[doInit] 备齐/校验注入参数；真正的
  /// Key/隐私注入由 AMapWidget 创建参数在原生工厂建图前完成）。
  /// 同一 Key 单飞、失败记录原因并可重试、Key 变了重新准备。
  Future<bool> runPluginInit(
    SettingsService settings,
    Future<void> Function() doInit,
  ) async {
    if (!canShowRealMap(settings)) return false;
    final before = gate.status;
    final ok = await gate.ensure(keyIdFor(settings), () async {
      await doInit();
      return true;
    });
    if (gate.status != before || ok) notifyListeners();
    return ok;
  }
}
