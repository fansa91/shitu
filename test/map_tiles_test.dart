import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:shitu/services/map_tiles.dart';

void main() {
  // 天安门（GCJ-02）——本应用全部坐标均为 GCJ-02。
  const tiananmenLat = 39.908722;
  const tiananmenLng = 116.397499;

  group('瓦片模板（2026-10-30 curl 实测通过的端点）', () {
    test('标准图：webrd + style=8', () {
      expect(
        AmapTileTemplates.standard,
        contains('webrd0{s}.is.autonavi.com/appmaptile'),
      );
      expect(AmapTileTemplates.standard, contains('style=8'));
      expect(AmapTileTemplates.standard, contains('x={x}&y={y}&z={z}'));
    });

    test('卫星：webst style=6 影像 + style=8 透明标注 overlay', () {
      expect(
        AmapTileTemplates.satellite,
        contains('webst0{s}.is.autonavi.com/appmaptile?style=6'),
      );
      expect(
        AmapTileTemplates.satelliteLabels,
        contains('webst0{s}.is.autonavi.com/appmaptile?style=8'),
      );
    });

    test('路况：tm.amap.com trafficengine 端点', () {
      expect(
        AmapTileTemplates.traffic,
        contains('tm.amap.com/trafficengine/mapabc/traffictile'),
      );
    });
  });

  group('GCJ-02 与高德瓦片对齐（默认 EPSG:3857 直喂，不做二次偏移）', () {
    test('自有瓦片号公式：天安门 z10 = 843/388（与 curl 实测取图的瓦片一致）', () {
      final t = amapTileCoord(
        latitude: tiananmenLat,
        longitude: tiananmenLng,
        zoom: 10,
      );
      expect(t.x, 843);
      expect(t.y, 388);
    });

    test('flutter_map 的 Epsg3857 投影把同一点投到同一张瓦片', () {
      // latLngToXY 的 scale = 瓦片边长 256 × 2^z；像素 / 256 即瓦片号。
      const crs = Epsg3857();
      final (px, py) = crs.latLngToXY(
        const LatLng(tiananmenLat, tiananmenLng),
        256.0 * 1024,
      );
      expect((px / 256).floor(), 843);
      expect((py / 256).floor(), 388);
    });

    test('瓦片号公式在其它缩放级与投影一致（z16 深圳）', () {
      const lat = 22.54554, lng = 114.05769; // 深圳市中心（初始相机）
      final t = amapTileCoord(latitude: lat, longitude: lng, zoom: 16);
      const crs = Epsg3857();
      final (px, py) = crs.latLngToXY(const LatLng(lat, lng), 256.0 * 65536);
      expect(t.x, (px / 256).floor());
      expect(t.y, (py / 256).floor());
    });
  });

  group('腾讯瓦片（2026-10-30 curl 实测，行号翻转锚定）', () {
    test('模板：矢量 rt 子域 + styleid=0；子域 0–3', () {
      expect(
        TencentTileTemplates.vector,
        contains('rt{s}.map.gtimg.com/tile'),
      );
      expect(TencentTileTemplates.vector, contains('type=vector&styleid=0'));
      expect(TencentTileTemplates.vector, contains('x={x}&y={y}'));
      expect(TencentTileTemplates.subdomains, ['0', '1', '2', '3']);
    });

    test('翻转公式：y_tx = (2^z − 1) − y_osm', () {
      expect(tencentFlippedY(osmY: 388, zoom: 10), 635);
      expect(tencentFlippedY(osmY: 24832, zoom: 16), 40703);
      expect(tencentFlippedY(osmY: 0, zoom: 1), 1);
    });

    test('天安门 z10 → (843, 635)：与高德同点 (843, 388) 翻转对应，实测同区', () {
      final t = tencentTileCoord(
        latitude: tiananmenLat,
        longitude: tiananmenLng,
        zoom: 10,
      );
      expect(t.x, 843);
      expect(t.y, 635);
    });

    test('天安门 z16 → (53957, 40703)：实测与高德 (53957, 24832) 地物对位', () {
      final t = tencentTileCoord(
        latitude: tiananmenLat,
        longitude: tiananmenLng,
        zoom: 16,
      );
      expect(t.x, 53957);
      expect(t.y, 40703);
    });

    test('卫星 URL：sateTiles 分组目录与文件名都用翻转坐标', () {
      final url = TencentTileTemplates.satelliteUrl(
        x: 53957,
        flippedY: 40703,
        zoom: 16,
      );
      // 分组目录 = 坐标 >> 4；子域按 (x + y) % 4 选取（此处余 0 → p0）。
      expect(url, 'https://p0.map.gtimg.com/sateTiles/16/3372/2543/53957_40703.jpg');
    });

    test('缩放上限：矢量/卫星 maxNativeZoom 均为 18（z19 实测为纯色占位）', () {
      expect(TencentTileTemplates.maxNativeZoom, 18);
    });

    test('图源属性：路况仅高德源可用；attribution 随源切换', () {
      expect(MapTileSource.amap.supportsTraffic, isTrue);
      expect(MapTileSource.tencent.supportsTraffic, isFalse);
      expect(MapTileSource.amap.attribution, contains('高德'));
      expect(MapTileSource.tencent.attribution, contains('腾讯'));
    });
  });
}
