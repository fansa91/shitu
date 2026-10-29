import 'dart:math' as math;

import '../models/geo_point.dart';

// 坐标系转换：GCJ-02（火星坐标，高德/腾讯）↔ BD-09（百度）↔ WGS-84（GPS）。
// 算法为业界通用的 coordtransform 实现，测试向量见 test/coord_test.dart。

const double _xPi = 3.14159265358979324 * 3000.0 / 180.0;
const double _a = 6378245.0;
const double _ee = 0.00669342162296594323;

/// BD-09 → GCJ-02（百度搜索/算路结果进 UI 层前必须调用）。
GeoPoint bd09ToGcj02(GeoPoint point) {
  final x = point.longitude - 0.0065;
  final y = point.latitude - 0.006;
  final z = math.sqrt(x * x + y * y) - 0.00002 * math.sin(y * _xPi);
  final theta = math.atan2(y, x) - 0.000003 * math.cos(x * _xPi);
  return GeoPoint(
    latitude: z * math.sin(theta),
    longitude: z * math.cos(theta),
  );
}

/// GCJ-02 → BD-09（向百度算路接口发请求前转换起终点）。
GeoPoint gcj02ToBd09(GeoPoint point) {
  final z = math.sqrt(point.longitude * point.longitude +
          point.latitude * point.latitude) +
      0.00002 * math.sin(point.latitude * _xPi);
  final theta = math.atan2(point.latitude, point.longitude) +
      0.000003 * math.cos(point.longitude * _xPi);
  return GeoPoint(
    latitude: z * math.sin(theta) + 0.006,
    longitude: z * math.cos(theta) + 0.0065,
  );
}

bool _outOfChina(double lng, double lat) =>
    lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271;

double _transformLat(double x, double y) {
  var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(x.abs());
  ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0;
  ret += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) * 2.0 / 3.0;
  ret += (160.0 * math.sin(y / 12.0 * math.pi) + 320 * math.sin(y * math.pi / 30.0)) * 2.0 / 3.0;
  return ret;
}

double _transformLng(double x, double y) {
  var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
  ret += (20.0 * math.sin(6.0 * x * math.pi) + 20.0 * math.sin(2.0 * x * math.pi)) * 2.0 / 3.0;
  ret += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) * 2.0 / 3.0;
  ret += (150.0 * math.sin(x / 12.0 * math.pi) + 300.0 * math.sin(x / 30.0 * math.pi)) * 2.0 / 3.0;
  return ret;
}

/// WGS-84（GPS 原始坐标）→ GCJ-02。中国境外直接返回原值。
GeoPoint wgs84ToGcj02(GeoPoint point) {
  final lng = point.longitude;
  final lat = point.latitude;
  if (_outOfChina(lng, lat)) return point;
  var dLat = _transformLat(lng - 105.0, lat - 35.0);
  var dLng = _transformLng(lng - 105.0, lat - 35.0);
  final radLat = lat / 180.0 * math.pi;
  var magic = math.sin(radLat);
  magic = 1 - _ee * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  dLat = (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * math.pi);
  dLng = (dLng * 180.0) / (_a / sqrtMagic * math.cos(radLat) * math.pi);
  return GeoPoint(latitude: lat + dLat, longitude: lng + dLng);
}
