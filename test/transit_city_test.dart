import 'package:flutter_test/flutter_test.dart';

import 'package:shitu/services/amap_web_service.dart';
import 'package:shitu/services/baidu_web_service.dart';
import 'package:shitu/services/map_data_service.dart';
import 'package:shitu/services/tencent_web_service.dart';

// 逆地理响应 fixture：按各家文档的 addressComponent 结构构造（不含真实数据请求）。
void main() {
  group('parseAmapRegeoCityJson', () {
    test('普通城市取 city', () {
      final json = <String, dynamic>{
        'status': '1',
        'regeocode': {
          'addressComponent': {'province': '广东省', 'city': '深圳市'},
        },
      };
      expect(parseAmapRegeoCityJson(json), '深圳市');
    });

    test('直辖市 city 为空数组时回落 province', () {
      final json = <String, dynamic>{
        'status': '1',
        'regeocode': {
          'addressComponent': {'province': '北京市', 'city': <dynamic>[]},
        },
      };
      expect(parseAmapRegeoCityJson(json), '北京市');
    });
  });

  group('parseBaiduRegeoCityJson', () {
    test('取 addressComponent.city', () {
      final json = <String, dynamic>{
        'status': 0,
        'result': {
          'addressComponent': {'province': '广东省', 'city': '深圳市'},
        },
      };
      expect(parseBaiduRegeoCityJson(json), '深圳市');
    });
  });

  group('parseTencentRegeoCityJson', () {
    test('取 address_component.city', () {
      final json = <String, dynamic>{
        'status': 0,
        'result': {
          'address_component': {'province': '广东省', 'city': '深圳市'},
        },
      };
      expect(parseTencentRegeoCityJson(json), '深圳市');
    });
  });

  group('resolveTransitCities 回落规则', () {
    test('两边都有：各用各的（跨城）', () {
      final r = resolveTransitCities(
          originCity: '深圳市', destinationCity: '广州市');
      expect(r.city, '深圳市');
      expect(r.cityd, '广州市');
    });

    test('起点缺失：用终点兜底两边', () {
      final r = resolveTransitCities(destinationCity: '广州市');
      expect(r.city, '广州市');
      expect(r.cityd, '广州市');
    });

    test('都缺失：均为 null', () {
      final r = resolveTransitCities();
      expect(r.city, isNull);
      expect(r.cityd, isNull);
    });
  });

  group('buildBaiduTransitParams', () {
    test('有城市时带 region 参数', () {
      final params = buildBaiduTransitParams(
        origin: '22.5,114.0',
        destination: '23.1,113.2',
        originCity: '深圳市',
        destinationCity: '广州市',
      );
      expect(params['origin_region'], '深圳市');
      expect(params['destination_region'], '广州市');
    });

    test('无城市时省略 region，走坐标解析', () {
      final params = buildBaiduTransitParams(
        origin: '22.5,114.0',
        destination: '22.6,114.1',
      );
      expect(params.containsKey('origin_region'), isFalse);
      expect(params.containsKey('destination_region'), isFalse);
    });
  });
}
