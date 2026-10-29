/// 兴趣点（搜索结果 / 收藏 / 历史记录的统一模型）。
class Poi {
  const Poi({
    required this.id,
    required this.name,
    required this.address,
    required this.distanceMeters,
    required this.category,
    this.tags = const [],
    this.phone,
    this.businessHours,
  });

  final String id;
  final String name;
  final String address;

  /// 距当前位置的直线距离（米）。
  final double distanceMeters;

  /// 分类，如「购物中心」「交通枢纽」。
  final String category;

  final List<String> tags;
  final String? phone;
  final String? businessHours;
}
