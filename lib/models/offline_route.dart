import 'geo_point.dart';
import 'map_provider.dart';

/// 本地保存的「离线路线」：只含路线数据（折线 + 分步文案 + 起终点摘要），
/// 不含地图底图。注意：amap_map 插件不提供离线地图下载能力，所以本应用
/// 的「离线」只到路线数据为止，查看时底图仍需联网加载（UI 会如实标注）。
class OfflineRoute {
  const OfflineRoute({
    required this.id,
    required this.originName,
    required this.destinationName,
    required this.mode,
    required this.provider,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.strategyTags,
    required this.points,
    required this.steps,
    required this.savedAtMs,
    this.originPoint,
    this.destinationPoint,
  });

  final String id;
  final String originName;
  final String destinationName;
  final TransportMode mode;
  final MapProvider provider;
  final int durationSeconds;
  final double distanceMeters;
  final List<String> strategyTags;

  /// 折线点（GCJ-02）。
  final List<GeoPoint> points;

  /// 分步导航文案；服务商未返回时为空。
  final List<String> steps;

  /// 保存时间（毫秒时间戳）。
  final int savedAtMs;

  final GeoPoint? originPoint;
  final GeoPoint? destinationPoint;

  DateTime get savedAt => DateTime.fromMillisecondsSinceEpoch(savedAtMs);

  Map<String, dynamic> toJson() => {
        'id': id,
        'originName': originName,
        'destinationName': destinationName,
        'mode': mode.name,
        'provider': provider.name,
        'durationSeconds': durationSeconds,
        'distanceMeters': distanceMeters,
        'strategyTags': strategyTags,
        'points': [for (final p in points) [p.latitude, p.longitude]],
        'steps': steps,
        'savedAtMs': savedAtMs,
        'originLat': originPoint?.latitude,
        'originLng': originPoint?.longitude,
        'destLat': destinationPoint?.latitude,
        'destLng': destinationPoint?.longitude,
      };

  factory OfflineRoute.fromJson(Map<String, dynamic> json) {
    GeoPoint? point(Object? lat, Object? lng) {
      final la = (lat as num?)?.toDouble();
      final ln = (lng as num?)?.toDouble();
      return (la != null && ln != null)
          ? GeoPoint(latitude: la, longitude: ln)
          : null;
    }

    return OfflineRoute(
      id: json['id']?.toString() ?? '',
      originName: json['originName']?.toString() ?? '',
      destinationName: json['destinationName']?.toString() ?? '',
      mode: TransportMode.values
              .where((m) => m.name == json['mode'])
              .firstOrNull ??
          TransportMode.driving,
      provider:
          MapProvider.values.where((p) => p.name == json['provider']).firstOrNull ??
              MapProvider.amap,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0,
      strategyTags: (json['strategyTags'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      points: [
        for (final raw in (json['points'] as List? ?? const []))
          if (raw is List && raw.length == 2)
            GeoPoint(
              latitude: (raw[0] as num).toDouble(),
              longitude: (raw[1] as num).toDouble(),
            ),
      ],
      steps:
          (json['steps'] as List? ?? const []).map((e) => e.toString()).toList(),
      savedAtMs: (json['savedAtMs'] as num?)?.toInt() ?? 0,
      originPoint: point(json['originLat'], json['originLng']),
      destinationPoint: point(json['destLat'], json['destLng']),
    );
  }
}
