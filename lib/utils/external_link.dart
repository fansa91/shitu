import 'package:url_launcher/url_launcher.dart';

import '../models/map_provider.dart';

/// 各家开放平台「获取 Key」的控制台地址（设置页 Key 卡下的外链按钮使用）。
abstract final class KeyConsoleUrls {
  /// 高德开放平台控制台（Web Key 与 Android/iOS SDK Key 都在这里创建）。
  static const amap = 'https://console.amap.com/dev/key/app';

  /// 百度地图开放平台控制台（AK 管理）。
  static const baidu = 'https://lbsyun.baidu.com/apiconsole/key#/home';

  /// 腾讯位置服务控制台（应用与 Key 管理）。
  static const tencent = 'https://lbs.qq.com/dev/console/application/mine';

  /// 英伟达 build.nvidia.com 的 API Key 管理页（生成 nvapi- 开头的 Key）。
  static const nvidia = 'https://build.nvidia.com/settings/api-keys';

  /// 按地图服务商返回对应的控制台地址。
  static String forProvider(MapProvider provider) {
    return switch (provider) {
      MapProvider.amap => amap,
      MapProvider.baidu => baidu,
      MapProvider.tencent => tencent,
    };
  }
}

/// 用系统浏览器打开外链；成功返回 true，失败返回 false（不抛异常）。
Future<bool> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
