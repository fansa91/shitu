import '../models/geo_point.dart';
import '../models/map_provider.dart';
import '../models/poi.dart';
import '../models/route_plan.dart';
import 'api_exception.dart';
import 'map_data_service.dart';
import 'web_api_client.dart';

/// 腾讯状态码 → 中文错误。status: 0 成功；110/111 签名/Key 类；
/// 120/121/140 配额/频率类；311 Key 无效等。
MapApiException tencentError(int status, String message) {
  final kind = switch (status) {
    110 || 111 || 311 || 312 => MapApiErrorKind.auth,
    120 || 121 || 140 || 141 => MapApiErrorKind.quota,
    _ => MapApiErrorKind.server,
  };
  final hint = switch (kind) {
    MapApiErrorKind.auth => '腾讯 Key 无效或签名/权限问题（status $status：$message）',
    MapApiErrorKind.quota => '腾讯调用配额/频率超限（status $status：$message）',
    _ => '腾讯服务错误：$message（status $status）',
  };
  return MapApiException(kind, hint);
}

Map<String, dynamic> _ensureTencentOk(Map<String, dynamic> json) {
  final status = json['status'];
  final code = status is num ? status.toInt() : -1;
  if (code != 0) {
    throw tencentError(code, json['message']?.toString() ?? '未知错误');
  }
  final result = json['result'];
  return result is Map<String, dynamic> ? result : const {};
}

/// 解析腾讯输入提示（place/v1/suggestion）响应（纯函数，供单测）。
/// data 项结构同搜索：title/address/category/location{lat,lng}。
List<Poi> parseTencentSuggestionJson(Map<String, dynamic> json) {
  _ensureTencentOk(json);
  final data = json['data'];
  if (data is! List) return const [];
  final pois = <Poi>[];
  for (final raw in data.whereType<Map<String, dynamic>>()) {
    final name = raw['title']?.toString() ?? '';
    if (name.isEmpty) continue;
    pois.add(Poi(
      id: raw['id']?.toString() ?? 'tencent-tip-$name',
      name: name,
      address: raw['address']?.toString() ?? '',
      category: raw['category']?.toString() ?? '',
      location: _tencentLocation(raw['location']),
    ));
  }
  return pois;
}

/// 解析腾讯地点搜索响应（纯函数，供 fixture 单测）。腾讯返回即 GCJ-02。
List<Poi> parseTencentSearchJson(Map<String, dynamic> json) {
  _ensureTencentOk(json);
  final data = json['data'];
  if (data is! List) return const [];
  return [
    for (final raw in data.whereType<Map<String, dynamic>>())
      Poi(
        id: 'tencent-${raw['id'] ?? raw['title']}',
        name: raw['title']?.toString() ?? '',
        address: raw['address']?.toString() ?? '',
        category: raw['category']?.toString() ?? '',
        phone: (raw['tel']?.toString().isEmpty ?? true)
            ? null
            : raw['tel'].toString(),
        location: _parseTencentLocation(raw['location']),
      ),
  ];
}

GeoPoint? _parseTencentLocation(Object? raw) {
  if (raw is! Map<String, dynamic>) return null;
  final lat = (raw['lat'] as num?)?.toDouble();
  final lng = (raw['lng'] as num?)?.toDouble();
  if (lat == null || lng == null) return null;
  return GeoPoint(latitude: lat, longitude: lng);
}

/// 解码腾讯路线 polyline：数组为 [lat, lng, dLat*1e6, dLng*1e6, ...]，
/// 首点为绝对值，其余为相对前一点的增量（单位 1e-6 度）。
List<GeoPoint> decodeTencentPolyline(List<dynamic> encoded) {
  if (encoded.length < 2) return const [];
  final points = <GeoPoint>[];
  var lat = (encoded[0] as num).toDouble();
  var lng = (encoded[1] as num).toDouble();
  points.add(GeoPoint(latitude: lat, longitude: lng));
  for (var i = 2; i + 1 < encoded.length; i += 2) {
    lat += (encoded[i] as num).toDouble() / 1e6;
    lng += (encoded[i + 1] as num).toDouble() / 1e6;
    points.add(GeoPoint(latitude: lat, longitude: lng));
  }
  return points;
}

/// 解析腾讯算路响应。注意腾讯 duration 单位是分钟，这里换算为秒。
List<RouteOption> parseTencentRouteJson(
  Map<String, dynamic> json, {
  required TransportMode mode,
}) {
  final result = _ensureTencentOk(json);
  final routes = result['routes'];
  if (routes is! List) return const [];
  final options = <RouteOption>[];
  for (final raw in routes.whereType<Map<String, dynamic>>()) {
    var points = <GeoPoint>[];
    final polyline = raw['polyline'];
    if (polyline is List && polyline.isNotEmpty) {
      points = decodeTencentPolyline(polyline);
    } else {
      // 公交等模式折线在 steps / lines 内。
      for (final step in (raw['steps'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()) {
        final stepLine = step['polyline'];
        if (stepLine is List) points.addAll(decodeTencentPolyline(stepLine));
        for (final line in (step['lines'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()) {
          final linePoints = line['polyline'];
          if (linePoints is List) {
            points.addAll(decodeTencentPolyline(linePoints));
          }
        }
      }
    }
    final tags = <String>[
      if (options.isEmpty) '推荐路线' else '备选路线',
      if ((raw['restriction'] as Map<String, dynamic>?)?['status'] == 0)
        '无限制',
    ];
    final steps = <String>[
      for (final step in (raw['steps'] as List? ?? const [])
          .whereType<Map<String, dynamic>>())
        if ((step['instruction']?.toString() ?? '').isNotEmpty)
          step['instruction'].toString(),
    ];
    options.add(RouteOption(
      durationSeconds: (((raw['duration'] as num?)?.toDouble() ?? 0) * 60).round(),
      distanceMeters: (raw['distance'] as num?)?.toDouble() ?? 0,
      tollYuan: (raw['toll'] as num?)?.toInt() ?? 0,
      trafficLights: 0, // 腾讯 direction v1 驾车响应不含红绿灯数
      strategyTags: tags,
      provider: MapProvider.tencent,
      recommended: options.isEmpty,
      points: points,
      steps: steps,
    ));
  }
  return options;
}

/// 解析腾讯逆地理编码响应 → 格式化地址（纯函数，供单测）。
String? parseTencentRegeoJson(Map<String, dynamic> json) {
  final result = _ensureTencentOk(json);
  final address = result['address']?.toString() ?? '';
  return address.isEmpty ? null : address;
}

/// 解析腾讯逆地理编码响应 → 城市名（纯函数，供单测）。
/// 腾讯公交接口不要求城市参数，此方法供接口一致性与后续功能使用。
String? parseTencentRegeoCityJson(Map<String, dynamic> json) {
  final result = _ensureTencentOk(json);
  final component = result['address_component'];
  if (component is Map<String, dynamic>) {
    final city = component['city']?.toString() ?? '';
    if (city.isNotEmpty) return city;
    final province = component['province']?.toString() ?? '';
    if (province.isNotEmpty) return province;
  }
  return null;
}

/// 腾讯 Web 服务真实实现。返回坐标即 GCJ-02，无需转换。
class TencentWebService implements MapDataService {
  TencentWebService({required this.keyProvider, WebApiClient? client})
      : _api = client ?? WebApiClient();

  final String Function() keyProvider;
  final WebApiClient _api;

  static const _providerName = '腾讯';

  @override
  bool get isSample => false;

  String get _key => keyProvider().trim();

  Uri _uri(String path, Map<String, String> params) =>
      Uri.https('apis.map.qq.com', path, {...params, 'key': _key});

  /// 腾讯接口用 lat,lng。
  String _latLng(GeoPoint p) => '${p.latitude},${p.longitude}';

  @override
  Future<List<Poi>> searchSuggestions(String query, MapProvider provider) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final json = await _api.getJson(
      _uri('/ws/place/v1/search', {
        'keyword': q,
        'boundary': 'region(全国,0)',
        'page_size': '20',
        'page_index': '1',
      }),
      providerName: _providerName,
    );
    return parseTencentSearchJson(json);
  }

  @override
  Future<List<Poi>> nearbyPois(MapProvider provider) async {
    final json = await _api.getJson(
      _uri('/ws/place/v1/search', {
        'keyword': '景点',
        'boundary': 'region(全国,0)',
        'page_size': '10',
        'page_index': '1',
      }),
      providerName: _providerName,
    );
    return parseTencentSearchJson(json);
  }

  @override
  Future<List<Poi>> inputTips(String query, MapProvider provider) async {
    if (query.trim().isEmpty) return const [];
    final json = await _api.getJson(
      _uri('/ws/place/v1/suggestion', {'keyword': query.trim()}),
      providerName: _providerName,
    );
    return parseTencentSuggestionJson(json);
  }

  @override
  Future<String?> reverseGeocode(GeoPoint point, MapProvider provider) async {
    try {
      final json = await _api.getJson(
        _uri('/ws/geocoder/v1/', {'location': _latLng(point)}),
        providerName: _providerName,
      );
      return parseTencentRegeoJson(json);
    } catch (_) {
      return null; // 逆地理只是补地名，失败不打断定位主流程
    }
  }

  @override
  Future<String?> reverseGeocodeCity(
      GeoPoint point, MapProvider provider) async {
    try {
      final json = await _api.getJson(
        _uri('/ws/geocoder/v1/', {'location': _latLng(point)}),
        providerName: _providerName,
      );
      return parseTencentRegeoCityJson(json);
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
      TransportMode.driving => '/ws/direction/v1/driving/',
      TransportMode.walking => '/ws/direction/v1/walking/',
      TransportMode.cycling => '/ws/direction/v1/bicycling/',
      TransportMode.transit => '/ws/direction/v1/transit/',
    };
    final json = await _api.getJson(
      _uri(endpoint, {'from': _latLng(o), 'to': _latLng(d)}),
      providerName: _providerName,
    );
    final options = parseTencentRouteJson(json, mode: mode);
    if (options.isEmpty) {
      throw const MapApiException(
        MapApiErrorKind.server,
        '腾讯未返回可用路线，请换个起终点重试',
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
      _uri('/ws/geocoder/v1/', {'address': '深圳市政府'}),
      providerName: _providerName,
    );
    _ensureTencentOk(json);
    return '连接成功：腾讯 Web Key 有效（地理编码验活通过）';
  }
}
