import '../models/map_provider.dart';
import '../models/poi.dart';
import '../models/route_plan.dart';

/// 地图数据服务抽象：搜索联想、附近 POI、多方案算路。
///
/// 正式版按 [MapProvider] 分别实现高德 / 百度 / 腾讯 Web API
/// （Key 由用户在设置页自填，请求时从 SettingsService 读取）。
abstract class MapDataService {
  Future<List<Poi>> searchSuggestions(String query, MapProvider provider);
  Future<List<Poi>> nearbyPois(MapProvider provider);
  Future<RoutePlan> planRoute({
    required String originName,
    required Poi destination,
    required TransportMode mode,
    required MapProvider provider,
  });
}

/// 骨架阶段的示例实现。
///
/// SAMPLE DATA: 返回的全部是写死的示例数据（深圳占位地名），
/// 不发起任何真实 API 请求，禁止冒充真实服务商数据。
class SampleMapDataService implements MapDataService {
  const SampleMapDataService();

  // sample data —— 示例 POI，仅用于骨架演示。
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
    ),
    Poi(
      id: 'sample-shenzhenbei',
      name: '深圳北站',
      address: '龙华区民治街道',
      distanceMeters: 6200,
      category: '交通枢纽',
      tags: ['高铁站', '地铁 4/5/6 号线'],
    ),
    Poi(
      id: 'sample-keji',
      name: '科技园',
      address: '南山区科苑路',
      distanceMeters: 2100,
      category: '产业园区',
      tags: ['写字楼聚集'],
    ),
    Poi(
      id: 'sample-lianhua',
      name: '莲花山公园',
      address: '福田区红荔路 6030 号',
      distanceMeters: 4800,
      category: '公园',
      tags: ['免费开放', '适合骑行'],
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
  Future<RoutePlan> planRoute({
    required String originName,
    required Poi destination,
    required TransportMode mode,
    required MapProvider provider,
  }) async {
    // sample data：按出行方式粗算两条示例路线（推荐 + 备选）。
    final distance = destination.distanceMeters * 1.35; // 示例绕行系数
    final (speedKmh, toll, lights) = switch (mode) {
      TransportMode.driving => (32.0, 5, 9),
      TransportMode.transit => (22.0, 0, 0),
      TransportMode.walking => (5.0, 0, 0),
      TransportMode.cycling => (15.0, 0, 0),
    };
    final baseSeconds = (distance / 1000 / speedKmh * 3600).round();
    return RoutePlan(
      originName: originName,
      destinationName: destination.name,
      mode: mode,
      options: [
        RouteOption(
          durationSeconds: baseSeconds,
          distanceMeters: distance,
          tollYuan: toll,
          trafficLights: lights,
          strategyTags: mode == TransportMode.driving
              ? const ['躲避拥堵', '推荐路线']
              : const ['推荐路线'],
          provider: provider,
          recommended: true,
        ),
        RouteOption(
          durationSeconds: (baseSeconds * 1.18).round(),
          distanceMeters: distance * 1.06,
          tollYuan: 0,
          trafficLights: lights == 0 ? 0 : lights + 5,
          strategyTags: const ['少收费', '距离稍长'],
          provider: provider,
        ),
      ],
    );
  }
}
