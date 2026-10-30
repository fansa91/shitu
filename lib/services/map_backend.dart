/// 地图渲染后端（AppMap 据此分流，见 widgets/app_map.dart）。
enum MapBackend {
  /// iOS 原生高德地图（vendored amap_flutter_map，MAMapKit 渲染）。
  nativeAmap,

  /// Web 瓦片（flutter_map + 高德/腾讯瓦片）。
  tiles,
}

/// 地图后端选择（纯函数，供单测）：
///
/// 只有「iOS + 已同意隐私 + 已填 iOS Key」三者齐备才走原生——iOS 的
/// MAMapKit/Metal 渲染在用户设备上一直正常（三期恢复）；没填 iOS Key
/// 或未同意隐私时 iOS 同样回落瓦片（不回 FakeMap 示意图）。
///
/// Android 恒瓦片：原生高德 GL 渲染器在目标机型上必崩（v0.2.1–v0.2.6
/// 两大 SDK 版本、两种视图类均死于渲染器启动），且 vendored 插件的
/// Android 侧已桩化（不注册视图、无 SDK 依赖与 .so），双保险；
/// 桌面端（Windows/macOS）没有原生实现，恒瓦片。
MapBackend selectMapBackend({
  required bool isIOS,
  required bool privacyAgreed,
  required String iosKey,
}) {
  if (isIOS && privacyAgreed && iosKey.trim().isNotEmpty) {
    return MapBackend.nativeAmap;
  }
  return MapBackend.tiles;
}
