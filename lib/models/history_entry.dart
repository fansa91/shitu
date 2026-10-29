import 'geo_point.dart';
import 'map_provider.dart';
import 'poi.dart';

/// 一条搜索历史：选中的 POI + 当时的搜索词 + 时间。
class SearchHistoryEntry {
  const SearchHistoryEntry({
    required this.poi,
    required this.query,
    required this.atMs,
  });

  final Poi poi;
  final String query;
  final int atMs;

  DateTime get at => DateTime.fromMillisecondsSinceEpoch(atMs);

  Map<String, dynamic> toJson() => {
        'poi': poi.toJson(),
        'query': query,
        'atMs': atMs,
      };

  factory SearchHistoryEntry.fromJson(Map<String, dynamic> json) {
    final poiJson = json['poi'];
    return SearchHistoryEntry(
      poi: poiJson is Map<String, dynamic>
          ? Poi.fromJson(poiJson)
          : const Poi(id: '', name: '', address: '', category: ''),
      query: json['query']?.toString() ?? '',
      atMs: (json['atMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 一条路线历史：起终点（名 + 坐标）、方式、数据源、时间。
/// 点开时可直接带入路线页重算（坐标缺失时终点仍可带入，起点回落 GPS）。
class RouteHistoryEntry {
  const RouteHistoryEntry({
    required this.originName,
    required this.destinationName,
    required this.mode,
    required this.provider,
    required this.atMs,
    this.originPoint,
    this.destinationPoint,
  });

  final String originName;
  final String destinationName;
  final GeoPoint? originPoint;
  final GeoPoint? destinationPoint;
  final TransportMode mode;
  final MapProvider provider;
  final int atMs;

  DateTime get at => DateTime.fromMillisecondsSinceEpoch(atMs);

  Map<String, dynamic> toJson() => {
        'originName': originName,
        'destinationName': destinationName,
        'mode': mode.name,
        'provider': provider.name,
        'atMs': atMs,
        'originLat': originPoint?.latitude,
        'originLng': originPoint?.longitude,
        'destLat': destinationPoint?.latitude,
        'destLng': destinationPoint?.longitude,
      };

  factory RouteHistoryEntry.fromJson(Map<String, dynamic> json) {
    GeoPoint? point(Object? lat, Object? lng) {
      final la = (lat as num?)?.toDouble();
      final ln = (lng as num?)?.toDouble();
      return (la != null && ln != null)
          ? GeoPoint(latitude: la, longitude: ln)
          : null;
    }

    return RouteHistoryEntry(
      originName: json['originName']?.toString() ?? '',
      destinationName: json['destinationName']?.toString() ?? '',
      mode: TransportMode.values
              .where((m) => m.name == json['mode'])
              .firstOrNull ??
          TransportMode.driving,
      provider:
          MapProvider.values.where((p) => p.name == json['provider']).firstOrNull ??
              MapProvider.amap,
      atMs: (json['atMs'] as num?)?.toInt() ?? 0,
      originPoint: point(json['originLat'], json['originLng']),
      destinationPoint: point(json['destLat'], json['destLng']),
    );
  }
}
