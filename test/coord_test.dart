import 'package:flutter_test/flutter_test.dart';

import 'package:shitu/models/geo_point.dart';
import 'package:shitu/utils/coord.dart';

// 期望值由业界通用 coordtransform 参考实现离线算得（WGS→GCJ 与公开已知向量一致）。
void main() {
  group('坐标转换已知向量', () {
    test('WGS-84 → GCJ-02（北京已知向量）', () {
      final gcj = wgs84ToGcj02(
        const GeoPoint(latitude: 39.915, longitude: 116.404),
      );
      expect(gcj.longitude, closeTo(116.41024449916938, 1e-6));
      expect(gcj.latitude, closeTo(39.91640428150164, 1e-6));
    });

    test('BD-09 → GCJ-02', () {
      final gcj = bd09ToGcj02(
        const GeoPoint(latitude: 39.915, longitude: 116.404),
      );
      expect(gcj.longitude, closeTo(116.39762729119315, 1e-6));
      expect(gcj.latitude, closeTo(39.90865673957631, 1e-6));
    });

    test('GCJ-02 → BD-09', () {
      final bd = gcj02ToBd09(
        const GeoPoint(latitude: 39.915, longitude: 116.404),
      );
      expect(bd.longitude, closeTo(116.41036949371029, 1e-6));
      expect(bd.latitude, closeTo(39.92133699351021, 1e-6));
    });

    test('GCJ → BD → GCJ 往返近似还原', () {
      const origin = GeoPoint(latitude: 22.545541, longitude: 114.118452);
      final back = bd09ToGcj02(gcj02ToBd09(origin));
      expect(back.longitude, closeTo(origin.longitude, 1e-4));
      expect(back.latitude, closeTo(origin.latitude, 1e-4));
    });

    test('境外坐标 WGS → GCJ 原样返回', () {
      const nyc = GeoPoint(latitude: 40.7128, longitude: -74.0060);
      expect(wgs84ToGcj02(nyc), nyc);
    });
  });
}
