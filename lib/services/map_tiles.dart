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

/// 底图来源（瓦片服务商）：底图轴与「数据源」（搜索/算路）相互独立。
enum MapTileSource {
  amap,
  tencent;

  String get label => switch (this) {
    MapTileSource.amap => '高德',
    MapTileSource.tencent => '腾讯',
  };

  /// 地图右下角的版权标注。
  String get attribution => switch (this) {
    MapTileSource.amap => '© 高德地图',
    MapTileSource.tencent => '© 腾讯地图',
  };

  /// 该来源是否提供实测可用的路况 overlay（路况层跟随图源，不能混叠：
  /// 各家路况瓦片只对得上自家网格）。腾讯路况 2026-10-30 实测未通过
  /// （见 [TencentTileTemplates] 类注释），故为 false。
  bool get supportsTraffic => this == MapTileSource.amap;
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

/// 腾讯 Web 瓦片（2026-10-30 本机 curl 实测，锚点同为天安门 GCJ-02）。
///
/// 腾讯瓦片同为 GCJ-02 + 普通 Web 墨卡托投影，但行号原点在**左下**
/// （TMS 式）：URL 的 y = (2^z − 1) − y_osm，见 [tencentFlippedY]。
/// z=16 实测对位决定性通过：翻转后 (53957, 40703) 与高德 (53957,
/// 24832) 同为长安街/护城河/天安门一带、地物逐项吻合；不翻转直取
/// (53957, 24832) 返回纯色空白图，反证翻转公式正确。
///
/// - 矢量 styleid=0（rt 子域）：z10/z16/z18 均真实数据 ✓ 采用；
/// z19 返回纯色占位图、z20 返回 400 ⇒ maxNativeZoom=18。
/// styleid 未给或给 1/5 等值时服务端忽略、回默认样式；styleid=2/3/4/8
/// 分别是深色/夜间/简洁等整幅底图样式，**都不是透明标注层**。
/// - 卫星（sateTiles）：路径含 16 张一组的分组目录 {x>>4}/{y>>4}，
/// 文件名 {x}_{y}.jpg，y 同样用翻转值。z16 实测为天安门城楼影像 ✓，
/// z18 有数据；子域 p0–p3 均通过。
/// - 卫星标注 overlay：**不存在**（逐个试过的 styleid 均为整幅底图），
/// 腾讯源的卫星样式只有影像、无路网标注——诚实降级，设置文案注明。
/// - 路况 overlay：**未通过**。p{s}.map.gtimg.com/traffic/{z}/{x>>4}/
/// {y>>4}/{x}_{y}.png 返回 404；rt 端点 type=traffic 参数被忽略、
/// 返回与矢量底图 md5 完全相同的图。故腾讯源下路况开关置灰
/// （[MapTileSource.supportsTraffic]）。
abstract final class TencentTileTemplates {
  /// 矢量底图（模板中的 {y} 是**翻转后**的行号，由
  /// TencentTileProvider 在生成 URL 时翻转，见 tile_map_view.dart）。
  static const vector =
      'https://rt{s}.map.gtimg.com/tile?z={z}&x={x}&y={y}&type=vector&styleid=0';

  /// 子域名分片（模板中的 {s}）：rt0–rt3 / p0–p3 均实测通过。
  static const subdomains = ['0', '1', '2', '3'];

  /// 瓦片有真实数据的最大原生缩放（见类注释的实测结论）。
  static const maxNativeZoom = 18;

  /// 卫星影像 URL（翻转后的行号 [flippedY]）：
  /// sateTiles 的分组目录与文件名都用翻转坐标，无法用 flutter_map
  /// 的 {x}/{y} 模板表达（需要 {x>>4} 这类计算占位），由
  /// TencentTileProvider 直接拼装。
  static String satelliteUrl({
    required int x,
    required int flippedY,
    required int zoom,
  }) {
    final s = subdomains[(x + flippedY) % subdomains.length];
    return 'https://p$s.map.gtimg.com/sateTiles/$zoom/${x >> 4}/${flippedY >> 4}/${x}_$flippedY.jpg';
  }
}

/// 腾讯瓦片行号翻转：y_tencent = (2^zoom − 1) − y_osm（纯函数，供测试锚定）。
int tencentFlippedY({required int osmY, required int zoom}) =>
    (1 << zoom) - 1 - osmY;

/// 腾讯瓦片号：先按标准 Slippy 公式算 OSM 号（见 [amapTileCoord]），
/// 再翻转行号。锚点（天安门 GCJ-02，2026-10-30 curl 实测对位）：
/// z10 → (843, 635)；z16 → (53957, 40703)。
({int x, int y}) tencentTileCoord({
  required double latitude,
  required double longitude,
  required int zoom,
}) {
  final osm = amapTileCoord(
    latitude: latitude,
    longitude: longitude,
    zoom: zoom,
  );
  return (x: osm.x, y: tencentFlippedY(osmY: osm.y, zoom: zoom));
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
