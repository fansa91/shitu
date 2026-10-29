import 'package:http/http.dart' as http;

import '../models/map_provider.dart';
import 'amap_web_service.dart';
import 'baidu_web_service.dart';
import 'map_data_service.dart';
import 'settings_service.dart';
import 'tencent_web_service.dart';
import 'web_api_client.dart';

/// 按服务商与 Key 构造真实 Web API 服务；Key 为空返回 null。
/// [key] 直接指定（设置页「测试连接」验未保存的输入框内容时用）。
MapDataService? createRealMapDataService(
  MapProvider provider, {
  required String key,
  http.Client? httpClient,
}) {
  if (key.trim().isEmpty) return null;
  final api = WebApiClient(client: httpClient);
  return switch (provider) {
    MapProvider.amap => AmapWebService(keyProvider: () => key, client: api),
    MapProvider.baidu => BaiduWebService(keyProvider: () => key, client: api),
    MapProvider.tencent =>
      TencentWebService(keyProvider: () => key, client: api),
  };
}

/// 服务工厂：当前服务商已填 Key → 真实 Web API 服务；
/// 未填 Key → 回退 [SampleMapDataService]（UI 必须标注「示例数据」）。
///
/// 真实服务的 Key 通过闭包在每次请求时从 [SettingsService] 读取，
/// 改 Key 后无需重启即可生效（区别于原生 SDK Key）。
class MapDataServices {
  MapDataServices(this._settings, {http.Client? httpClient}) {
    _httpClient = httpClient;
  }

  final SettingsService _settings;
  http.Client? _httpClient;
  final Map<MapProvider, MapDataService> _realCache = {};
  static const _sample = SampleMapDataService();

  bool isSampleFor(MapProvider provider) =>
      _settings.keyFor(provider).trim().isEmpty;

  MapDataService serviceFor(MapProvider provider) {
    if (isSampleFor(provider)) return _sample;
    return _realCache.putIfAbsent(provider, () {
      final api = WebApiClient(client: _httpClient);
      return switch (provider) {
        MapProvider.amap => AmapWebService(
            keyProvider: () => _settings.keyFor(provider),
            client: api,
          ),
        MapProvider.baidu => BaiduWebService(
            keyProvider: () => _settings.keyFor(provider),
            client: api,
          ),
        MapProvider.tencent => TencentWebService(
            keyProvider: () => _settings.keyFor(provider),
            client: api,
          ),
      };
    });
  }

  /// 当前设置选中的服务商对应的服务。
  MapDataService get current => serviceFor(_settings.provider);
}
