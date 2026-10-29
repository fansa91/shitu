import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shitu/models/map_provider.dart';
import 'package:shitu/services/amap_web_service.dart';
import 'package:shitu/services/api_exception.dart';
import 'package:shitu/services/baidu_web_service.dart';
import 'package:shitu/services/tencent_web_service.dart';

// 解析层 fixture 测试：JSON 按三家官方文档的响应格式构造，
// 不依赖真实网络与真实 Key。
Map<String, dynamic> _fixture(String name) {
  final text = File('test/fixtures/$name').readAsStringSync();
  return jsonDecode(text) as Map<String, dynamic>;
}

void main() {
  group('高德解析', () {
    test('place/text 搜索：名称/地址/分类/坐标（lng,lat 串）', () {
      final pois = parseAmapSearchJson(_fixture('amap_search.json'));
      expect(pois, hasLength(2));
      expect(pois.first.name, '深圳万象城');
      expect(pois.first.category, '购物服务');
      expect(pois.first.location?.longitude, closeTo(114.118452, 1e-9));
      expect(pois.first.location?.latitude, closeTo(22.545541, 1e-9));
      expect(pois.first.phone, '0755-82328888');
      expect(pois[1].phone, isNull); // 空 tel → null
    });

    test('驾车路线：时长/距离/过路费/红绿灯/折线点数', () {
      final options = parseAmapDrivingJson(
        _fixture('amap_driving.json'),
        strategyTag: '速度优先',
        recommended: true,
      );
      expect(options, hasLength(1));
      final o = options.first;
      expect(o.durationSeconds, 2280);
      expect(o.distanceMeters, 12400);
      expect(o.tollYuan, 5);
      expect(o.trafficLights, 9);
      expect(o.strategyTags, ['速度优先']);
      expect(o.recommended, isTrue);
      expect(o.points, hasLength(4));
      expect(o.points.first.longitude, closeTo(113.934527, 1e-9));
      expect(o.points.last.latitude, closeTo(22.545, 1e-9));
    });

    test('步行路线：简单 paths 解析', () {
      final options = parseAmapSimpleRouteJson(
        _fixture('amap_walking.json'),
        mode: TransportMode.walking,
      );
      expect(options, hasLength(1));
      expect(options.first.durationSeconds, 1680);
      expect(options.first.points, hasLength(2));
    });

    test('错误响应：infocode 10001 → 鉴权错误（中文）', () {
      expect(
        () => parseAmapSearchJson(
            {'status': '0', 'info': 'INVALID_USER_KEY', 'infocode': '10001'}),
        throwsA(isA<MapApiException>()
            .having((e) => e.kind, 'kind', MapApiErrorKind.auth)
            .having((e) => e.message, 'message', contains('Key 无效'))),
      );
    });
  });

  group('百度解析', () {
    test('地点搜索：BD-09 坐标必须转成 GCJ-02', () {
      final pois = parseBaiduSearchJson(_fixture('baidu_search.json'));
      expect(pois, hasLength(1));
      expect(pois.first.name, '深圳市民中心');
      // BD-09 (114.064551, 22.548456) → GCJ-02 参考值
      expect(pois.first.location?.longitude, closeTo(114.057999, 1e-4));
      expect(pois.first.location?.latitude, closeTo(22.542799, 1e-4));
    });

    test('驾车路线：字段解析 + 折线逐点转 GCJ-02', () {
      final options = parseBaiduRouteJson(
        _fixture('baidu_driving.json'),
        mode: TransportMode.driving,
      );
      expect(options, hasLength(1));
      final o = options.first;
      expect(o.durationSeconds, 2280);
      expect(o.distanceMeters, 12400);
      expect(o.tollYuan, 5);
      expect(o.points, hasLength(4));
      expect(o.points.first.longitude, closeTo(114.057999, 1e-4));
      expect(o.points.first.latitude, closeTo(22.542799, 1e-4));
    });

    test('错误响应：status 5 → AK 鉴权错误', () {
      expect(
        () => parseBaiduSearchJson({'status': 5, 'message': 'AK不存在'}),
        throwsA(isA<MapApiException>()
            .having((e) => e.kind, 'kind', MapApiErrorKind.auth)),
      );
    });
  });

  group('腾讯解析', () {
    test('地点搜索：GCJ-02 坐标直通', () {
      final pois = parseTencentSearchJson(_fixture('tencent_search.json'));
      expect(pois, hasLength(1));
      expect(pois.first.name, '深圳万象城');
      expect(pois.first.location?.longitude, closeTo(114.118452, 1e-9));
      expect(pois.first.location?.latitude, closeTo(22.545541, 1e-9));
    });

    test('驾车路线：duration 分钟换算秒 + polyline 增量解码', () {
      final options = parseTencentRouteJson(
        _fixture('tencent_driving.json'),
        mode: TransportMode.driving,
      );
      expect(options, hasLength(1));
      final o = options.first;
      expect(o.durationSeconds, 38 * 60);
      expect(o.distanceMeters, 12400);
      expect(o.tollYuan, 5);
      expect(o.points, hasLength(3));
      expect(o.points[0].latitude, closeTo(22.543096, 1e-6));
      expect(o.points[1].latitude, closeTo(22.544096, 1e-6));
      expect(o.points[1].longitude, closeTo(114.058865, 1e-6));
      expect(o.points[2].latitude, closeTo(22.544596, 1e-6));
      expect(o.points[2].longitude, closeTo(114.060365, 1e-6));
    });

    test('错误响应：status 311 → Key 鉴权错误', () {
      expect(
        () => parseTencentSearchJson({'status': 311, 'message': 'key不存在'}),
        throwsA(isA<MapApiException>()
            .having((e) => e.kind, 'kind', MapApiErrorKind.auth)),
      );
    });
  });

  group('分步文案与逆地理编码', () {
    test('高德驾车：steps 提取 instruction', () {
      final options = parseAmapDrivingJson(
        _fixture('amap_driving.json'),
        strategyTag: '速度优先',
      );
      expect(options.first.steps, isNotEmpty);
      expect(options.first.steps.first, '向东出发');
    });

    test('百度驾车：steps 提取 instructions 并去 HTML', () {
      final options = parseBaiduRouteJson(
        _fixture('baidu_driving.json'),
        mode: TransportMode.driving,
      );
      expect(options.first.steps, isNotEmpty);
      expect(options.first.steps.first, '向东出发');
      expect(stripHtmlTags('沿<b>深南大道</b>行驶'), '沿深南大道行驶');
    });

    test('高德逆地理：取 formatted_address', () {
      final address = parseAmapRegeoJson({
        'status': '1',
        'infocode': '10000',
        'regeocode': {'formatted_address': '广东省深圳市南山区科技园'},
      });
      expect(address, '广东省深圳市南山区科技园');
      expect(parseAmapRegeoJson({'status': '1', 'regeocode': {}}), isNull);
    });

    test('百度逆地理：取 result.formatted_address', () {
      final address = parseBaiduRegeoJson({
        'status': 0,
        'result': {'formatted_address': '广东省深圳市南山区科苑路'},
      });
      expect(address, '广东省深圳市南山区科苑路');
    });

    test('腾讯逆地理：取 result.address', () {
      final address = parseTencentRegeoJson({
        'status': 0,
        'message': 'query ok',
        'result': {'address': '广东省深圳市南山区科苑南路'},
      });
      expect(address, '广东省深圳市南山区科苑南路');
    });
  });
}
