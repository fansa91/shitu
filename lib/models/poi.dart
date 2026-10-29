import 'geo_point.dart';

/// 兴趣点（搜索结果 / 收藏 / 历史记录的统一模型）。
class Poi {
  const Poi({
    required this.id,
    required this.name,
    required this.address,
    this.distanceMeters,
    required this.category,
    this.tags = const [],
    this.phone,
    this.businessHours,
    this.location,
  });

  final String id;
  final String name;
  final String address;

  /// 距当前位置的直线距离（米）；真实 Web API 搜索通常不返回，缺失为 null。
  final double? distanceMeters;

  /// 坐标（GCJ-02）。真实服务商结果必带；示例/手填起点可缺失。
  final GeoPoint? location;

  /// 分类，如「购物中心」「交通枢纽」。
  final String category;

  final List<String> tags;
  final String? phone;
  final String? businessHours;
}
