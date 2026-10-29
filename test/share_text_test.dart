import 'package:flutter_test/flutter_test.dart';

import 'package:shitu/models/geo_point.dart';
import 'package:shitu/models/map_provider.dart';
import 'package:shitu/models/poi.dart';
import 'package:shitu/models/route_plan.dart';
import 'package:shitu/utils/share_text.dart';

const poi = Poi(
  id: 'x',
  name: '深圳万象城',
  address: '宝安南路1881号',
  category: '购物',
  location: GeoPoint(latitude: 22.545541, longitude: 114.118452),
);

void main() {
  test('POI 分享：名称+地址+高德链接（经度在前）', () {
    final text = poiShareText(poi);
    expect(text, contains('深圳万象城'));
    expect(text, contains('宝安南路1881号'));
    expect(
      text,
      contains(
          'https://uri.amap.com/marker?position=114.118452,22.545541&name='),
    );
  });

  test('POI 无坐标：只分享名称与地址', () {
    const noLoc = Poi(id: 'y', name: '无名小店', address: '某街道', category: '');
    final text = poiShareText(noLoc);
    expect(text, '无名小店\n某街道');
  });

  test('路线分享：起终点/方式/时长距离/数据源/终点链接', () {
    const option = RouteOption(
      durationSeconds: 2280,
      distanceMeters: 12500,
      tollYuan: 0,
      trafficLights: 9,
      strategyTags: ['推荐'],
      provider: MapProvider.amap,
    );
    final text = routeShareText(
      originName: '我的位置',
      destination: poi,
      mode: TransportMode.driving,
      provider: MapProvider.amap,
      option: option,
    );
    expect(text, contains('我的位置 → 深圳万象城'));
    expect(text, contains('数据源：高德地图'));
    expect(text, contains('uri.amap.com/marker'));
  });
}
