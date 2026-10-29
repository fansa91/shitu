import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shitu/models/geo_point.dart';
import 'package:shitu/models/map_provider.dart';
import 'package:shitu/models/offline_route.dart';
import 'package:shitu/models/poi.dart';
import 'package:shitu/services/places_service.dart';

const _poiA = Poi(
  id: 'amap-1',
  name: '万象城',
  address: '宝安南路 1881 号',
  category: '购物中心',
  tags: ['停车场充足'],
  phone: '0755-0000',
  location: GeoPoint(latitude: 22.545541, longitude: 114.118452),
);
const _poiB = Poi(
  id: 'amap-2',
  name: '深圳北站',
  address: '龙华区民治街道',
  category: '交通枢纽',
  location: GeoPoint(latitude: 22.609826, longitude: 114.029113),
);

OfflineRoute _route(String id) => OfflineRoute(
      id: id,
      originName: '我的位置',
      destinationName: '万象城',
      mode: TransportMode.driving,
      provider: MapProvider.amap,
      durationSeconds: 2280,
      distanceMeters: 12400,
      strategyTags: const ['躲避拥堵'],
      points: const [
        GeoPoint(latitude: 22.54, longitude: 113.93),
        GeoPoint(latitude: 22.5455, longitude: 114.118),
      ],
      steps: const ['向东出发', '到达目的地'],
      savedAtMs: 1760000000000,
      originPoint: const GeoPoint(latitude: 22.54, longitude: 113.93),
      destinationPoint: const GeoPoint(latitude: 22.5455, longitude: 114.118),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PlacesService 家/公司', () {
    test('设置后重载仍能读回（往返持久化）', () async {
      final service = PlacesService();
      await service.load();
      expect(service.home, isNull);
      expect(service.work, isNull);

      await service.setHome(_poiA);
      await service.setWork(_poiB);

      final reloaded = PlacesService();
      await reloaded.load();
      expect(reloaded.home?.id, 'amap-1');
      expect(reloaded.home?.name, '万象城');
      expect(reloaded.home?.location?.latitude, closeTo(22.545541, 1e-9));
      expect(reloaded.home?.tags, ['停车场充足']);
      expect(reloaded.work?.id, 'amap-2');
    });

    test('清除后重载为空', () async {
      final service = PlacesService();
      await service.load();
      await service.setHome(_poiA);
      await service.setHome(null);
      final reloaded = PlacesService();
      await reloaded.load();
      expect(reloaded.home, isNull);
    });
  });

  group('PlacesService 收藏', () {
    test('toggle 增删 + 持久化往返', () async {
      final service = PlacesService();
      await service.load();

      expect(await service.toggleFavorite(_poiA), isTrue);
      expect(await service.toggleFavorite(_poiB), isTrue);
      expect(service.favorites.map((p) => p.id), ['amap-2', 'amap-1']);
      expect(service.isFavorite('amap-1'), isTrue);

      expect(await service.toggleFavorite(_poiA), isFalse);
      expect(service.isFavorite('amap-1'), isFalse);

      final reloaded = PlacesService();
      await reloaded.load();
      expect(reloaded.favorites.map((p) => p.id), ['amap-2']);

      await reloaded.removeFavorite('amap-2');
      final again = PlacesService();
      await again.load();
      expect(again.favorites, isEmpty);
    });
  });

  group('PlacesService 离线路线', () {
    test('保存/删除 + 折线与步骤往返', () async {
      final service = PlacesService();
      await service.load();
      await service.saveOfflineRoute(_route('r1'));
      await service.saveOfflineRoute(_route('r2'));

      final reloaded = PlacesService();
      await reloaded.load();
      expect(reloaded.offlineRoutes.map((r) => r.id), ['r2', 'r1']);
      final r = reloaded.offlineRoutes.last;
      expect(r.originName, '我的位置');
      expect(r.destinationName, '万象城');
      expect(r.mode, TransportMode.driving);
      expect(r.points, hasLength(2));
      expect(r.points.first.latitude, closeTo(22.54, 1e-9));
      expect(r.steps, ['向东出发', '到达目的地']);
      expect(r.savedAtMs, 1760000000000);
      expect(r.destinationPoint?.longitude, closeTo(114.118, 1e-9));

      await reloaded.removeOfflineRoute('r1');
      final again = PlacesService();
      await again.load();
      expect(again.offlineRoutes.map((x) => x.id), ['r2']);
    });

    test('同 id 保存视为更新，不重复', () async {
      final service = PlacesService();
      await service.load();
      await service.saveOfflineRoute(_route('r1'));
      await service.saveOfflineRoute(_route('r1'));
      expect(service.offlineRoutes, hasLength(1));
    });
  });
}
