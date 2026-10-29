import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shitu/services/amap_web_service.dart';
import 'package:shitu/services/baidu_web_service.dart';
import 'package:shitu/services/tencent_web_service.dart';

// 联想接口解析 fixture 测试：JSON 按三家官方文档格式构造，不用真实 Key。
Map<String, dynamic> _fixture(String name) {
  final text = File('test/fixtures/$name').readAsStringSync();
  return jsonDecode(text) as Map<String, dynamic>;
}

void main() {
  test('高德 inputtips：名称/区县+地址/坐标，空数组字段防御', () {
    final pois = parseAmapInputTipsJson(_fixture('amap_inputtips.json'));
    expect(pois, hasLength(2));
    expect(pois.first.name, '深圳万象城');
    expect(pois.first.address, '广东省深圳市罗湖区宝安南路1881号');
    expect(pois.first.location?.longitude, closeTo(114.118452, 1e-9));
    // 第二条 address/id/location 都是空数组 → 地址回落区县、无坐标、有兜底 id
    expect(pois[1].address, '广东省深圳市罗湖区');
    expect(pois[1].location, isNull);
    expect(pois[1].id, isNotEmpty);
  });

  test('百度 suggestion：城市+区县作地址，BD-09 转 GCJ-02', () {
    final pois = parseBaiduSuggestionJson(_fixture('baidu_suggestion.json'));
    expect(pois, hasLength(2));
    expect(pois.first.name, '深圳万象城');
    expect(pois.first.address, '深圳市罗湖区');
    expect(pois.first.category, '购物');
    // BD-09(114.124891, 22.551976) → GCJ-02 应向西南偏移约数百米
    final loc = pois.first.location!;
    expect(loc.longitude, lessThan(114.124891));
    expect(loc.latitude, lessThan(22.551976));
    expect(loc.longitude, greaterThan(114.10));
  });

  test('腾讯 suggestion：title/地址/分类/坐标直取', () {
    final pois =
        parseTencentSuggestionJson(_fixture('tencent_suggestion.json'));
    expect(pois, hasLength(2));
    expect(pois.first.name, '深圳万象城');
    expect(pois.first.address, '广东省深圳市罗湖区宝安南路1881号');
    expect(pois.first.location?.latitude, closeTo(22.545541, 1e-9));
  });
}
