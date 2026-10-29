import '../models/geo_point.dart';
import '../models/map_provider.dart';
import '../models/poi.dart';
import '../models/route_plan.dart';

/// 地图数据服务抽象：搜索联想、附近 POI、多方案算路、连接验活。
///
/// 真实实现按 [MapProvider] 分别对接高德 / 百度 / 腾讯 Web API
/// （Key 由用户在设置页自填，请求时从 SettingsService 读取）；
/// 无 Key 时由工厂回退到 [SampleMapDataService]。
abstract class MapDataService {
  /// 是否为示例数据实现（UI 必须据此明确标注「示例数据」）。
  bool get isSample;

  Future<List<Poi>> searchSuggestions(String query, MapProvider provider);
  Future<List<Poi>> nearbyPois(MapProvider provider);

  /// 逆地理编码：坐标 → 格式化地址。取不到（无 Key / 接口失败）返回 null，
  /// 调用方据此回退展示「我的位置（定位坐标）」，不要抛错打断定位主流程。
  Future<String?> reverseGeocode(GeoPoint point, MapProvider provider);

  /// 逆地理编码取所在城市名（公交算路拼 city 参数用）。
  /// 取不到返回 null，调用方按 [resolveTransitCities] 的回落规则处理。
  Future<String?> reverseGeocodeCity(GeoPoint point, MapProvider provider);
  Future<RoutePlan> planRoute({
    required Poi origin,
    required Poi destination,
    required TransportMode mode,
    required MapProvider provider,
  });

  /// 验活：真实实现发一次轻量请求；示例实现直接返回说明文案。
  Future<String> testConnection();
}

/// 公交算路的城市参数回落规则（纯函数，供单测）：
/// 起点城市优先，缺失时用终点城市兜底；终点城市（cityd）反之。
/// 两边都取不到 → 都为 null，由各服务按自家要求处理
/// （高德必填 → 抛中文提示；百度/腾讯可省略走坐标解析）。
({String? city, String? cityd}) resolveTransitCities({
  String? originCity,
  String? destinationCity,
}) {
  return (
    city: originCity ?? destinationCity,
    cityd: destinationCity ?? originCity,
  );
}

/// 示例实现。
///
/// SAMPLE DATA: 返回的全部是写死的示例数据（深圳占位地名与坐标），
/// 不发起任何真实 API 请求，禁止冒充真实服务商数据。
class SampleMapDataService implements MapDataService {
  const SampleMapDataService();

  @override
  bool get isSample => true;

  // sample data —— 示例 POI，仅用于演示（坐标为深圳占位点，GCJ-02）。
  static const List<Poi> samplePois = [
    Poi(
      id: 'sample-wanxiangcheng',
      name: '万象城（罗湖店）',
      address: '宝安南路 1881 号',
      distanceMeters: 3400,
      category: '购物中心',
      tags: ['停车场充足', '地铁 1/2 号线'],
      phone: '0755-8232 0000（示例）',
      businessHours: '10:00–22:00',
      location: GeoPoint(latitude: 22.545541, longitude: 114.118452),
    ),
    Poi(
      id: 'sample-shenzhenbei',
      name: '深圳北站',
      address: '龙华区民治街道',
      distanceMeters: 6200,
      category: '交通枢纽',
      tags: ['高铁站', '地铁 4/5/6 号线'],
      location: GeoPoint(latitude: 22.609826, longitude: 114.029113),
    ),
    Poi(
      id: 'sample-keji',
      name: '科技园',
      address: '南山区科苑路',
      distanceMeters: 2100,
      category: '产业园区',
      tags: ['写字楼聚集'],
      location: GeoPoint(latitude: 22.540503, longitude: 113.934527),
    ),
    Poi(
      id: 'sample-lianhua',
      name: '莲花山公园',
      address: '福田区红荔路 6030 号',
      distanceMeters: 4800,
      category: '公园',
      tags: ['免费开放', '适合骑行'],
      location: GeoPoint(latitude: 22.554307, longitude: 114.051325),
    ),
  ];

  @override
  Future<List<Poi>> searchSuggestions(
    String query,
    MapProvider provider,
  ) async {
    // sample data：按名称/地址简单过滤模拟联想。
    final q = query.trim();
    if (q.isEmpty) return samplePois;
    return samplePois
        .where((p) => p.name.contains(q) || p.address.contains(q))
        .toList();
  }

  @override
  Future<List<Poi>> nearbyPois(MapProvider provider) async => samplePois;

  @override
  Future<String?> reverseGeocode(GeoPoint point, MapProvider provider) async =>
      null; // 示例模式不做逆地理编码

  @override
  Future<String?> reverseGeocodeCity(
          GeoPoint point, MapProvider provider) async =>
      null; // 示例模式不查城市，公交走示例路线不需要城市参数

  @override
  Future<RoutePlan> planRoute({
    required Poi origin,
    required Poi destination,
    required TransportMode mode,
    required MapProvider provider,
  }) async {
    // sample data：按出行方式粗算两条示例路线（推荐 + 备选）。
    final distance = (destination.distanceMeters ?? 3000) * 1.35; // 示例绕行系数
    final (speedKmh, toll, lights) = switch (mode) {
      TransportMode.driving => (32.0, 5.0, 9),
      TransportMode.transit => (22.0, 0, 0),
      TransportMode.walking => (5.0, 0, 0),
      TransportMode.cycling => (15.0, 0, 0),
    };
    final baseSeconds = (distance / 1000 / speedKmh * 3600).round();
    // 两端都有坐标时给一条直线折线，供地图绘制演示。
    final line = <GeoPoint>[
      if (origin.location != null) origin.location!,
      if (destination.location != null) destination.location!,
    ];
    return RoutePlan(
      originName: origin.name,
      destinationName: destination.name,
      mode: mode,
      options: [
        RouteOption(
          durationSeconds: baseSeconds,
          distanceMeters: distance,
          tollYuan: toll.round(),
          trafficLights: lights,
          strategyTags: mode == TransportMode.driving
              ? const ['躲避拥堵', '推荐路线']
              : const ['推荐路线'],
          provider: provider,
          recommended: true,
          points: line,
          steps: [
            '从「${origin.name}」出发',
            '沿示例道路前往「${destination.name}」（示例数据）',
            '到达目的地',
          ],
        ),
        RouteOption(
          durationSeconds: (baseSeconds * 1.18).round(),
          distanceMeters: distance * 1.06,
          tollYuan: 0,
          trafficLights: lights == 0 ? 0 : lights + 5,
          strategyTags: const ['少收费', '距离稍长'],
          provider: provider,
          points: line,
        ),
      ],
    );
  }

  @override
  Future<String> testConnection() async =>
      '示例模式：未发起真实请求（先填写 Key 再测试）';
}
