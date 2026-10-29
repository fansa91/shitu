import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shitu/models/geo_point.dart';
import 'package:shitu/models/map_provider.dart';
import 'package:shitu/models/poi.dart';
import 'package:shitu/services/history_service.dart';

const poiA = Poi(
  id: 'a',
  name: '万象城',
  address: '宝安南路',
  category: '购物',
  location: GeoPoint(latitude: 22.54, longitude: 114.11),
);
const poiB = Poi(
  id: 'b',
  name: '深圳北站',
  address: '龙华区',
  category: '交通',
  location: GeoPoint(latitude: 22.60, longitude: 114.02),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('搜索历史：去重、最新在前、往返与清空', () async {
    final service = HistoryService();
    await service.load();
    await service.addSearch(poiA, '万象');
    await service.addSearch(poiB, '北站');
    await service.addSearch(poiA, '万象城'); // 同 id 去重并置顶
    expect(service.searches.map((e) => e.poi.id), ['a', 'b']);
    expect(service.searches.first.query, '万象城');

    final reloaded = HistoryService();
    await reloaded.load();
    expect(reloaded.searches.map((e) => e.poi.id), ['a', 'b']);

    await reloaded.clearSearches();
    expect(reloaded.searches, isEmpty);
  });

  test('搜索历史上限 20 条滚动淘汰', () async {
    final service = HistoryService();
    await service.load();
    for (var i = 0; i < 25; i++) {
      await service.addSearch(
        Poi(id: 'p$i', name: '地点$i', address: '', category: ''),
        'q$i',
      );
    }
    expect(service.searches, hasLength(HistoryService.maxEntries));
    expect(service.searches.first.poi.id, 'p24');
    expect(service.searches.last.poi.id, 'p5');
  });

  test('路线历史：按起终点+方式去重、往返与清空', () async {
    final service = HistoryService();
    await service.load();
    await service.addRoute(
      originName: '我的位置',
      destinationName: '万象城',
      mode: TransportMode.driving,
      provider: MapProvider.amap,
      destinationPoint: poiA.location,
    );
    await service.addRoute(
      originName: '我的位置',
      destinationName: '万象城',
      mode: TransportMode.transit, // 方式不同，不算重复
      provider: MapProvider.amap,
    );
    await service.addRoute(
      originName: '我的位置',
      destinationName: '万象城',
      mode: TransportMode.driving, // 与第一条重复 → 置顶去重
      provider: MapProvider.baidu,
      destinationPoint: poiA.location,
    );
    expect(service.routes, hasLength(2));
    expect(service.routes.first.mode, TransportMode.driving);

    final reloaded = HistoryService();
    await reloaded.load();
    expect(reloaded.routes, hasLength(2));
    expect(reloaded.routes.first.destinationPoint, poiA.location);

    await reloaded.clearRoutes();
    expect(reloaded.routes, isEmpty);
  });
}
