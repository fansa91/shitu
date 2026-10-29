import '../models/geo_point.dart';
import '../models/map_provider.dart';
import '../models/poi.dart';
import '../models/route_plan.dart';
import 'api_exception.dart';
import 'map_data_service.dart';
import 'web_api_client.dart';

/// 高德状态码 → 中文错误。infocode 见高德 Web 服务错误码表。
MapApiException amapError(String infocode, String info) {
  final kind = switch (infocode) {
    // Key 无效 / IP/签名不符 / 未开通权限等鉴权类
    '10001' ||
    '10005' ||
    '10006' ||
    '10007' ||
    '10008' ||
    '10009' ||
    '10012' ||
    '10013' =>
      MapApiErrorKind.auth,
    // 日访问量超限 / 访问过频等配额类
    '10003' || '10004' || '10021' || '10044' => MapApiErrorKind.quota,
    _ => MapApiErrorKind.server,
  };
  final hint = switch (kind) {
    MapApiErrorKind.auth => '高德 Key 无效或未开通对应服务（infocode $infocode）',
    MapApiErrorKind.quota => '高德调用配额/频率超限（infocode $infocode）',
    _ => '高德服务错误：$info（infocode $infocode）',
  };
  return MapApiException(kind, hint);
}

void _ensureAmapOk(Map<String, dynamic> json) {
  if (json['status']?.toString() != '1') {
    throw amapError(
      json['infocode']?.toString() ?? '',
      json['info']?.toString() ?? '未知错误',
    );
  }
}

double _asDouble(Object? v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
int _asInt(Object? v) =>
    v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

/// 解析高德文本折线 "lng,lat;lng,lat" → GeoPoint 列表（高德返回即 GCJ-02）。
List<GeoPoint> parseAmapPolyline(String text) {
  final points = <GeoPoint>[];
  for (final pair in text.split(';')) {
    final parts = pair.split(',');
    if (parts.length != 2) continue;
    final lng = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lat != null && lng != null) {
      points.add(GeoPoint(latitude: lat, longitude: lng));
    }
  }
  return points;
}

/// 解析 place/text 搜索响应（纯函数，供单测以 fixture 验证）。
List<Poi> parseAmapSearchJson(Map<String, dynamic> json) {
  _ensureAmapOk(json);
  final pois = json['pois'];
  if (pois is! List) return const [];
  return [
    for (final raw in pois.whereType<Map<String, dynamic>>())
      Poi(
        id: 'amap-${raw['id'] ?? raw['name']}',
        name: raw['name']?.toString() ?? '',
        address: raw['address']?.toString() ?? '',
        category: (raw['type']?.toString() ?? '').split(';').first,
        phone: (raw['tel']?.toString().isEmpty ?? true)
            ? null
            : raw['tel'].toString(),
        location: _parseAmapLocation(raw['location']?.toString() ?? ''),
      ),
  ];
}

GeoPoint? _parseAmapLocation(String text) {
  final parts = text.split(',');
  if (parts.length != 2) return null;
  final lng = double.tryParse(parts[0]);
  final lat = double.tryParse(parts[1]);
  if (lat == null || lng == null) return null;
  return GeoPoint(latitude: lat, longitude: lng);
}

/// 解析驾车响应中的 paths（一个 strategy 一次请求）→ 方案列表。
List<RouteOption> parseAmapDrivingJson(
  Map<String, dynamic> json, {
  required String strategyTag,
  bool recommended = false,
}) {
  _ensureAmapOk(json);
  final paths = (json['route'] as Map<String, dynamic>?)?['paths'];
  if (paths is! List) return const [];
  return [
    for (final raw in paths.whereType<Map<String, dynamic>>())
      RouteOption(
        durationSeconds: _asInt(raw['duration']),
        distanceMeters: _asDouble(raw['distance']),
        tollYuan: _asInt(raw['tolls']),
        trafficLights: _asInt(raw['traffic_lights']),
        strategyTags: [strategyTag],
        provider: MapProvider.amap,
        recommended: recommended,
        points: [
          for (final step in (raw['steps'] as List? ?? const [])
              .whereType<Map<String, dynamic>>())
            ...parseAmapPolyline(step['polyline']?.toString() ?? ''),
        ],
      ),
  ];
}

/// 解析步行/骑行响应（结构同驾车 paths，但无 tolls/traffic_lights）。
List<RouteOption> parseAmapSimpleRouteJson(
  Map<String, dynamic> json, {
  required TransportMode mode,
}) {
  _ensureAmapOk(json);
  final paths = (json['route'] as Map<String, dynamic>?)?['paths'];
  if (paths is! List) return const [];
  return [
    for (final raw in paths.whereType<Map<String, dynamic>>())
      RouteOption(
        durationSeconds: _asInt(raw['duration']),
        distanceMeters: _asDouble(raw['distance']),
        tollYuan: 0,
        trafficLights: 0,
        strategyTags: const ['推荐路线'],
        provider: MapProvider.amap,
        recommended: true,
        points: [
          for (final step in (raw['steps'] as List? ?? const [])
              .whereType<Map<String, dynamic>>())
            ...parseAmapPolyline(step['polyline']?.toString() ?? ''),
        ],
      ),
  ];
}

/// 解析公交响应 route.transits。
List<RouteOption> parseAmapTransitJson(Map<String, dynamic> json) {
  _ensureAmapOk(json);
  final transits = (json['route'] as Map<String, dynamic>?)?['transits'];
  if (transits is! List) return const [];
  final options = <RouteOption>[];
  for (final raw in transits.whereType<Map<String, dynamic>>()) {
    final points = <GeoPoint>[];
    final lines = <String>[];
    for (final seg in (raw['segments'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()) {
      final walking = seg['walking'] as Map<String, dynamic>?;
      for (final step in (walking?['steps'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()) {
        points.addAll(parseAmapPolyline(step['polyline']?.toString() ?? ''));
      }
      final bus = seg['bus'] as Map<String, dynamic>?;
      for (final line in (bus?['buslines'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()) {
        final name = line['name']?.toString() ?? '';
        if (name.isNotEmpty) lines.add(name.split('(').first);
        final polyline =
            (line['polyline'] as Map<String, dynamic>?)?['polyline'];
        points.addAll(parseAmapPolyline(polyline?.toString() ?? ''));
      }
    }
    final cost = raw['cost'] as Map<String, dynamic>? ?? raw;
    options.add(RouteOption(
      durationSeconds: _asInt(cost['duration'] ?? raw['duration']),
      distanceMeters: _asDouble(raw['distance']),
      tollYuan: 0,
      trafficLights: 0,
      strategyTags: lines.isEmpty ? const ['公交方案'] : lines.take(3).toList(),
      provider: MapProvider.amap,
      recommended: options.isEmpty,
      points: points,
    ));
  }
  return options;
}

/// 高德 Web 服务真实实现。Key 通过 [keyProvider] 在每次请求时读取，
/// 保证设置页改 Key 后无需重建服务即生效。
class AmapWebService implements MapDataService {
  AmapWebService({required this.keyProvider, WebApiClient? client})
      : _api = client ?? WebApiClient();

  final String Function() keyProvider;
  final WebApiClient _api;

  static const _providerName = '高德';

  @override
  bool get isSample => false;

  String get _key => keyProvider().trim();

  Uri _uri(String path, Map<String, String> params) =>
      Uri.https('restapi.amap.com', path, {...params, 'key': _key});

  String _lngLat(GeoPoint p) => '${p.longitude},${p.latitude}';

  @override
  Future<List<Poi>> searchSuggestions(String query, MapProvider provider) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final json = await _api.getJson(
      _uri('/v3/place/text', {
        'keywords': q,
        'offset': '20',
        'page': '1',
        'extensions': 'base',
      }),
      providerName: _providerName,
    );
    return parseAmapSearchJson(json);
  }

  @override
  Future<List<Poi>> nearbyPois(MapProvider provider) async {
    // 无设备定位时以城市地标类关键词近似「附近推荐」。
    final json = await _api.getJson(
      _uri('/v3/place/text', {
        'keywords': '景点',
        'offset': '10',
        'page': '1',
        'extensions': 'base',
      }),
      providerName: _providerName,
    );
    return parseAmapSearchJson(json);
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
    final originText = _lngLat(o);
    final destText = _lngLat(d);
    final List<RouteOption> options;
    switch (mode) {
      case TransportMode.driving:
        options = await _planDriving(originText, destText);
      case TransportMode.walking:
        final json = await _api.getJson(
          _uri('/v3/direction/walking',
              {'origin': originText, 'destination': destText}),
          providerName: _providerName,
        );
        options = parseAmapSimpleRouteJson(json, mode: mode);
      case TransportMode.cycling:
        final json = await _api.getJson(
          _uri('/v3/direction/riding',
              {'origin': originText, 'destination': destText}),
          providerName: _providerName,
        );
        options = parseAmapSimpleRouteJson(json, mode: mode);
      case TransportMode.transit:
        final json = await _api.getJson(
          _uri('/v3/direction/transit/integrated', {
            'origin': originText,
            'destination': destText,
            'city': '深圳',
            'cityd': '深圳',
          }),
          providerName: _providerName,
        );
        options = parseAmapTransitJson(json);
    }
    if (options.isEmpty) {
      throw const MapApiException(
        MapApiErrorKind.server,
        '高德未返回可用路线，请换个起终点重试',
      );
    }
    return RoutePlan(
      originName: origin.name,
      destinationName: destination.name,
      mode: mode,
      options: options,
    );
  }

  /// 驾车多方案：三种 strategy 并行请求后拼成方案列表。
  /// strategy 取值（v3）：0 速度优先、1 费用优先（少收费）、4 躲避拥堵。
  Future<List<RouteOption>> _planDriving(String origin, String dest) async {
    const strategies = <(String, String)>[
      ('0', '速度优先'),
      ('4', '躲避拥堵'),
      ('1', '少收费'),
    ];
    final results = await Future.wait([
      for (final (code, _) in strategies)
        _api
            .getJson(
              _uri('/v3/direction/driving', {
                'origin': origin,
                'destination': dest,
                'strategy': code,
                'extensions': 'base',
              }),
              providerName: _providerName,
            )
            .then<Map<String, dynamic>?>((v) => v)
            .onError((_, _) => null),
    ]);
    final options = <RouteOption>[];
    for (var i = 0; i < strategies.length; i++) {
      final json = results[i];
      if (json == null) continue;
      try {
        options.addAll(parseAmapDrivingJson(
          json,
          strategyTag: strategies[i].$2,
          recommended: i == 0,
        ));
      } on MapApiException {
        continue; // 单个策略失败不拖垮其它方案
      }
    }
    // 按时长排序，首条标推荐。
    options.sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));
    return [
      for (var i = 0; i < options.length; i++)
        RouteOption(
          durationSeconds: options[i].durationSeconds,
          distanceMeters: options[i].distanceMeters,
          tollYuan: options[i].tollYuan,
          trafficLights: options[i].trafficLights,
          strategyTags: options[i].strategyTags,
          provider: options[i].provider,
          recommended: i == 0,
          points: options[i].points,
        ),
    ];
  }

  @override
  Future<String> testConnection() async {
    final json = await _api.getJson(
      _uri('/v3/geocode/geo', {'address': '深圳市政府'}),
      providerName: _providerName,
    );
    _ensureAmapOk(json);
    return '连接成功：高德 Web Key 有效（地理编码验活通过）';
  }
}
