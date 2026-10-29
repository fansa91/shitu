import '../models/geo_point.dart';
import '../models/map_provider.dart';
import '../models/poi.dart';
import '../models/route_plan.dart';
import '../utils/coord.dart';
import 'api_exception.dart';
import 'map_data_service.dart';
import 'web_api_client.dart';

/// 百度状态码 → 中文错误。status: 0 成功；2 参数错误；4 配额/并发超限；
/// 5 AK 无效（权限校验失败）；401/402 配额类（部分接口）。
MapApiException baiduError(int status, String message) {
  final kind = switch (status) {
    4 || 401 || 402 => MapApiErrorKind.quota,
    5 || 101 || 102 => MapApiErrorKind.auth,
    _ => MapApiErrorKind.server,
  };
  final hint = switch (kind) {
    MapApiErrorKind.quota => '百度调用配额/频率超限（status $status：$message）',
    MapApiErrorKind.auth => '百度 AK 无效或未开通对应服务（status $status：$message）',
    _ => '百度服务错误：$message（status $status）',
  };
  return MapApiException(kind, hint);
}

Map<String, dynamic> _ensureBaiduOk(Map<String, dynamic> json) {
  final status = json['status'];
  final code = status is num ? status.toInt() : -1;
  if (code != 0) {
    throw baiduError(code, json['message']?.toString() ?? '未知错误');
  }
  final result = json['result'];
  return result is Map<String, dynamic> ? result : const {};
}

/// 解析百度地点搜索响应（纯函数，供 fixture 单测）。
/// 注意：百度返回 BD-09 坐标，这里统一转 GCJ-02 再进 UI 层。
List<Poi> parseBaiduSearchJson(Map<String, dynamic> json) {
  _ensureBaiduOk(json);
  final results = json['results'];
  if (results is! List) return const [];
  return [
    for (final raw in results.whereType<Map<String, dynamic>>())
      Poi(
        id: 'baidu-${raw['uid'] ?? raw['name']}',
        name: raw['name']?.toString() ?? '',
        address: raw['address']?.toString() ?? '',
        category: '',
        location: _parseBaiduLocation(raw['location']),
      ),
  ];
}

GeoPoint? _parseBaiduLocation(Object? raw) {
  if (raw is! Map<String, dynamic>) return null;
  final lat = (raw['lat'] as num?)?.toDouble();
  final lng = (raw['lng'] as num?)?.toDouble();
  if (lat == null || lng == null) return null;
  return bd09ToGcj02(GeoPoint(latitude: lat, longitude: lng));
}

/// 百度分步文案带 HTML 标签（如 <b>），展示前去掉。
String stripHtmlTags(String text) =>
    text.replaceAll(RegExp(r'<[^>]*>'), '').trim();

/// 解析百度算路响应。steps[].path 为 BD-09 的 "lng,lat;..." 串，
/// 逐点转 GCJ-02；公交 steps 无 path 时用起讫站坐标兜底连线。
List<RouteOption> parseBaiduRouteJson(
  Map<String, dynamic> json, {
  required TransportMode mode,
}) {
  final result = _ensureBaiduOk(json);
  final routes = result['routes'];
  if (routes is! List) return const [];
  final options = <RouteOption>[];
  for (final raw in routes.whereType<Map<String, dynamic>>()) {
    final points = <GeoPoint>[];
    final steps = <String>[];
    for (final step in (raw['steps'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()) {
      final path = step['path']?.toString() ?? step['traffics']?.toString() ?? '';
      for (final pair in path.split(';')) {
        final parts = pair.split(',');
        if (parts.length != 2) continue;
        final lng = double.tryParse(parts[0]);
        final lat = double.tryParse(parts[1]);
        if (lat != null && lng != null) {
          points.add(bd09ToGcj02(GeoPoint(latitude: lat, longitude: lng)));
        }
      }
      final instruction =
          stripHtmlTags(step['instructions']?.toString() ?? '');
      if (instruction.isNotEmpty) steps.add(instruction);
    }
    options.add(RouteOption(
      durationSeconds: (raw['duration'] as num?)?.toInt() ?? 0,
      distanceMeters: (raw['distance'] as num?)?.toDouble() ?? 0,
      tollYuan: (raw['toll'] as num?)?.toInt() ?? 0,
      trafficLights: 0, // 百度 direction v2 不返回红绿灯数
      strategyTags: options.isEmpty ? const ['推荐路线'] : const ['备选路线'],
      provider: MapProvider.baidu,
      recommended: options.isEmpty,
      points: points,
      steps: steps,
    ));
  }
  return options;
}

/// 解析百度逆地理编码响应 → 格式化地址（纯函数，供单测）。
String? parseBaiduRegeoJson(Map<String, dynamic> json) {
  final result = _ensureBaiduOk(json);
  final address = result['formatted_address']?.toString() ?? '';
  return address.isEmpty ? null : address;
}

/// 解析百度逆地理编码响应 → 城市名（纯函数，供单测）。
String? parseBaiduRegeoCityJson(Map<String, dynamic> json) {
  final result = _ensureBaiduOk(json);
  final component = result['addressComponent'];
  if (component is! Map<String, dynamic>) return null;
  final city = component['city']?.toString() ?? '';
  return city.isEmpty ? null : city;
}

/// 百度公交（direction/v2/transit）参数拼装（纯函数，供单测）：
/// 查到城市时带 origin_region / destination_region（跨城必传），
/// 查不到则省略，百度按坐标自行解析同城公交。
Map<String, String> buildBaiduTransitParams({
  required String origin,
  required String destination,
  String? originCity,
  String? destinationCity,
}) {
  final cities = resolveTransitCities(
    originCity: originCity,
    destinationCity: destinationCity,
  );
  return {
    'origin': origin,
    'destination': destination,
    if (cities.city != null) 'origin_region': cities.city!,
    if (cities.cityd != null) 'destination_region': cities.cityd!,
  };
}

/// 百度 Web 服务真实实现。坐标进出统一转换：
/// 请求前 GCJ-02 → BD-09，响应折线/POI 的 BD-09 → GCJ-02。
class BaiduWebService implements MapDataService {
  BaiduWebService({required this.keyProvider, WebApiClient? client})
      : _api = client ?? WebApiClient();

  final String Function() keyProvider;
  final WebApiClient _api;

  static const _providerName = '百度';

  @override
  bool get isSample => false;

  String get _key => keyProvider().trim();

  Uri _uri(String path, Map<String, String> params) => Uri.https(
        'api.map.baidu.com',
        path,
        {...params, 'ak': _key, 'output': 'json'},
      );

  /// 百度接口用 lat,lng 且为 BD-09。
  String _bdLatLng(GeoPoint gcj) {
    final bd = gcj02ToBd09(gcj);
    return '${bd.latitude},${bd.longitude}';
  }

  @override
  Future<List<Poi>> searchSuggestions(String query, MapProvider provider) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final json = await _api.getJson(
      _uri('/place/v2/search', {
        'query': q,
        'region': '全国',
        'city_limit': 'false',
        'page_size': '20',
      }),
      providerName: _providerName,
    );
    return parseBaiduSearchJson(json);
  }

  @override
  Future<List<Poi>> nearbyPois(MapProvider provider) async {
    final json = await _api.getJson(
      _uri('/place/v2/search', {
        'query': '景点',
        'region': '全国',
        'city_limit': 'false',
        'page_size': '10',
      }),
      providerName: _providerName,
    );
    return parseBaiduSearchJson(json);
  }

  @override
  Future<String?> reverseGeocode(GeoPoint point, MapProvider provider) async {
    try {
      final json = await _api.getJson(
        _uri('/reverse_geocoding/v3/', {
          'location': _bdLatLng(point),
          'coordtype': 'bd09ll',
        }),
        providerName: _providerName,
      );
      return parseBaiduRegeoJson(json);
    } catch (_) {
      return null; // 逆地理只是补地名，失败不打断定位主流程
    }
  }

  @override
  Future<String?> reverseGeocodeCity(
      GeoPoint point, MapProvider provider) async {
    try {
      final json = await _api.getJson(
        _uri('/reverse_geocoding/v3/', {
          'location': _bdLatLng(point),
          'coordtype': 'bd09ll',
        }),
        providerName: _providerName,
      );
      return parseBaiduRegeoCityJson(json);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<RoutePlan> planRoute({
    required Poi origin,
    required Poi destination,
    required TransportMode mode,
    required MapProvider provider,
  }) async {
    final o = origin.location;
    final d = destination.location;
    if (o == null || d == null) {
      throw MapApiException(
        MapApiErrorKind.precondition,
        o == null
            ? '起点「${origin.name}」没有坐标：请在起点框输入具体地点后重试'
            : '终点「${destination.name}」没有坐标',
      );
    }
    final endpoint = switch (mode) {
      TransportMode.driving => '/direction/v2/driving',
      TransportMode.walking => '/direction/v2/walking',
      TransportMode.cycling => '/direction/v2/riding',
      TransportMode.transit => '/direction/v2/transit',
    };
    final params = mode == TransportMode.transit
        ? buildBaiduTransitParams(
            origin: _bdLatLng(o),
            destination: _bdLatLng(d),
            originCity: await reverseGeocodeCity(o, provider),
            destinationCity: await reverseGeocodeCity(d, provider),
          )
        : {'origin': _bdLatLng(o), 'destination': _bdLatLng(d)};
    final json = await _api.getJson(
      _uri(endpoint, params),
      providerName: _providerName,
    );
    final options = parseBaiduRouteJson(json, mode: mode);
    if (options.isEmpty) {
      throw const MapApiException(
        MapApiErrorKind.server,
        '百度未返回可用路线，请换个起终点重试',
      );
    }
    return RoutePlan(
      originName: origin.name,
      destinationName: destination.name,
      mode: mode,
      options: options,
    );
  }

  @override
  Future<String> testConnection() async {
    final json = await _api.getJson(
      _uri('/geocoding/v3/', {'address': '深圳市政府'}),
      providerName: _providerName,
    );
    _ensureBaiduOk(json);
    return '连接成功：百度 Web AK 有效（地理编码验活通过）';
  }
}
