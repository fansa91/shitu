import 'dart:math' as math;

/// 底图样式：瓦片图层组合（标准 / 卫星）。
enum MapBaseStyle {
  standard,
  satellite;

  String get label => switch (this) {
    MapBaseStyle.standard => '标准',
    MapBaseStyle.satellite => '卫星',
  };
}

/// 高德 Web 瓦片地址模板（flutter_map 的 {x}/{y}/{z}/{s} 占位）。
///
/// 2026-10-30 本机 curl 实测结论（z=10 北京天安门，瓦片 843/388）：
/// - 标准 style=8（webrd）：HTTP 200，PNG 256×256 不透明 ✓ 采用；
/// style=7 同样 200/PNG，作为备选记录、未启用。
/// - 卫星 style=6（webst）：HTTP 200，JPEG 256×256 影像 ✓ 采用。
/// - 卫星标注 style=8（webst）：HTTP 200，RGBA PNG、约 63% 像素全透明
/// ✓ 是透明路网/标注 overlay，叠在卫星影像之上采用。
/// - 路况（tm.amap.com/trafficengine）：HTTP 200，RGBA PNG、约 71%
/// 透明，非透明像素为绿/黄/红路况色带 ✓ 采用；无路况数据的区域
/// 该端点返回 404，图层侧用 errorTileCallback 吞掉、保持透明。
/// traffic.amap.com 同路径实测连接失败，不用。
/// - 缩放上限：z=18 瓦片有真实数据（数 KB），z=19/20 只回 179B 空白
/// 占位图，故各图层 maxNativeZoom=18，超过后由 flutter_map 放大
/// z18 瓦片（overzoom），MapOptions.maxZoom 仍可到 20。
abstract final class AmapTileTemplates {
  /// 标准底图（矢量风格渲染的栅格瓦片）。
  static const standard =
      'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}';

  /// 卫星影像（无标注）。
  static const satellite =
      'https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}';

  /// 卫星标注 overlay（透明 PNG：路网 + 地名）。
  static const satelliteLabels =
      'https://webst0{s}.is.autonavi.com/appmaptile?style=8&x={x}&y={y}&z={z}';

  /// 实时路况 overlay（透明 PNG；无数据区域 404，图层侧忽略）。
  static const traffic =
      'https://tm.amap.com/trafficengine/mapabc/traffictile?v=1.0&t=1&x={x}&y={y}&z={z}';

  /// 子域名分片（模板中的 {s}）：与高德官方 webrd0X/webst0X 一致取 1–4。
  static const subdomains = ['1', '2', '3', '4'];

  /// 瓦片有真实数据的最大原生缩放（见类注释的实测结论）。
  static const maxNativeZoom = 18;
}

/// 标准 Web 墨卡托（Slippy Map）瓦片号计算，纯函数，供测试锚定与排查用；
/// flutter_map 内部用同样的公式（EPSG:3857）取瓦片。
///
/// 本应用全部数据是 GCJ-02；高德瓦片本身就是把 GCJ-02
/// 坐标当作经纬度、按普通 Web 墨卡托投影渲染出来的（瓦片图上的道路
/// 位置与 GCJ-02 坐标一一对应）。因此 flutter_map 用默认 EPSG:3857、
/// 直接喂 GCJ-02 坐标，投影出的瓦片号正好是高德为这组坐标渲染的
/// 那张瓦片，天然对齐——切勿再做 WGS-84/GCJ-02 之类的二次偏移转换，
/// 那样反而会整体错位约数百米。
({int x, int y}) amapTileCoord({
  required double latitude,
  required double longitude,
  required int zoom,
}) {
  final n = math.pow(2, zoom).toDouble();
  final clampedLat = latitude.clamp(-85.05112878, 85.05112878);
  final latRad = clampedLat * math.pi / 180.0;
  var x = ((longitude + 180.0) / 360.0 * n).floor();
  var y =
      ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
              2.0 *
              n)
          .floor();
  final maxIndex = n.toInt() - 1;
  x = x.clamp(0, maxIndex);
  y = y.clamp(0, maxIndex);
  return (x: x, y: y);
}
