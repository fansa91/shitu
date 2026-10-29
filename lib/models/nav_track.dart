import 'geo_point.dart';

/// 一条已保存的导航轨迹（GPS 实走轨迹，GCJ-02）。
class NavTrack {
  const NavTrack({
    required this.id,
    required this.name,
    required this.originName,
    required this.destinationName,
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.startedAtMs,
  });

  final String id;

  /// 展示名，默认「起点 → 终点 + 日期」。
  final String name;
  final String originName;
  final String destinationName;

  /// 轨迹点（GCJ-02，按时间顺序）。
  final List<GeoPoint> points;

  /// 实际里程（米，按轨迹点累计）。
  final double distanceMeters;

  /// 实际用时（秒）。
  final int durationSeconds;

  /// 开始时刻（毫秒时间戳）。
  final int startedAtMs;

  DateTime get startedAt => DateTime.fromMillisecondsSinceEpoch(startedAtMs);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'originName': originName,
        'destinationName': destinationName,
        'points': [for (final p in points) [p.latitude, p.longitude]],
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
        'startedAtMs': startedAtMs,
      };

  factory NavTrack.fromJson(Map<String, dynamic> json) {
    return NavTrack(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      originName: json['originName']?.toString() ?? '',
      destinationName: json['destinationName']?.toString() ?? '',
      points: [
        for (final raw in (json['points'] as List? ?? const []))
          if (raw is List && raw.length == 2)
            GeoPoint(
              latitude: (raw[0] as num).toDouble(),
              longitude: (raw[1] as num).toDouble(),
            ),
      ],
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      startedAtMs: (json['startedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}
