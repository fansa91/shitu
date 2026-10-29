/// 经纬度坐标点。全 App 内部统一使用 GCJ-02 坐标系；
/// 百度 BD-09 在服务层进出时转换，不进 UI 层。
class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}
