import '../models/map_provider.dart';
import '../models/poi.dart';
import '../models/route_plan.dart';
import 'format.dart';

/// 高德地图标记链接（uri.amap.com/marker）：经度,纬度 + 名称。
String amapMarkerLink(Poi poi) {
  final loc = poi.location!;
  return 'https://uri.amap.com/marker'
      '?position=${loc.longitude},${loc.latitude}'
      '&name=${Uri.encodeComponent(poi.name)}';
}

/// POI 分享文案：名称 + 地址 +（有坐标时）高德链接。纯函数，供单测。
String poiShareText(Poi poi) {
  final lines = [poi.name, if (poi.address.isNotEmpty) poi.address];
  if (poi.location != null) lines.add(amapMarkerLink(poi));
  return lines.join('\n');
}

/// 路线分享文案：起点→终点、方式、时长、距离、数据源 + 终点链接。
/// 纯函数，供单测。
String routeShareText({
  required String originName,
  required Poi destination,
  required TransportMode mode,
  required MapProvider provider,
  required RouteOption option,
}) {
  final lines = [
    '$originName → ${destination.name}',
    '${mode.displayName} · ${formatDuration(option.durationSeconds)} · '
        '${formatDistance(option.distanceMeters)} · '
        '数据源：${provider.displayName}',
  ];
  if (destination.location != null) lines.add(amapMarkerLink(destination));
  return lines.join('\n');
}
