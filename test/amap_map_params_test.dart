import 'package:flutter_test/flutter_test.dart';
import 'package:shitu/services/amap_map_params.dart';

void main() {
  group('resolveAmapMapStageParams 创建段（裸创建）', () {
    test('未 created 时一切可选参数都不下发、倾斜归 0', () {
      final p = resolveAmapMapStageParams(
        created: false,
        compatMode: false,
        trafficEnabled: true,
        tilt: 58,
      );
      expect(p.overlaysEnabled, isFalse);
      expect(p.myLocationStyleEnabled, isFalse);
      expect(p.trafficEnabled, isFalse);
      expect(p.buildingsEnabled, isFalse);
      expect(p.scaleEnabled, isFalse);
      expect(p.labelsEnabled, isFalse);
      expect(p.touchPoiEnabled, isFalse);
      expect(p.initialTilt, 0);
    });

    test('未 created 时兼容模式不改变裸创建结果', () {
      final p = resolveAmapMapStageParams(
        created: false,
        compatMode: true,
        trafficEnabled: false,
        tilt: 0,
      );
      expect(p.overlaysEnabled, isFalse);
      expect(p.myLocationStyleEnabled, isFalse);
      expect(p.initialTilt, 0);
    });
  });

  group('resolveAmapMapStageParams 就绪段（完整参数）', () {
    test('created 后下发叠加物与定位样式，业务值原样透传', () {
      final p = resolveAmapMapStageParams(
        created: true,
        compatMode: false,
        trafficEnabled: true,
        tilt: 58,
      );
      expect(p.overlaysEnabled, isTrue);
      expect(p.myLocationStyleEnabled, isTrue);
      expect(p.trafficEnabled, isTrue);
      expect(p.buildingsEnabled, isTrue); // tilt>0 时开建筑（旧语义）
      expect(p.scaleEnabled, isTrue);
      expect(p.labelsEnabled, isTrue);
      expect(p.touchPoiEnabled, isTrue);
      expect(p.initialTilt, 58);
    });

    test('2D（tilt=0）时建筑不开、路况关时透传关', () {
      final p = resolveAmapMapStageParams(
        created: true,
        compatMode: false,
        trafficEnabled: false,
        tilt: 0,
      );
      expect(p.buildingsEnabled, isFalse);
      expect(p.trafficEnabled, isFalse);
      expect(p.initialTilt, 0);
    });

    test('兼容模式叠加在就绪段之上：可选渲染项全关、倾斜归 0', () {
      final p = resolveAmapMapStageParams(
        created: true,
        compatMode: true,
        trafficEnabled: true,
        tilt: 58,
      );
      expect(p.overlaysEnabled, isTrue); // 叠加物仍下发，兼容模式只关渲染项
      expect(p.myLocationStyleEnabled, isTrue);
      expect(p.trafficEnabled, isFalse);
      expect(p.buildingsEnabled, isFalse);
      expect(p.scaleEnabled, isFalse);
      expect(p.labelsEnabled, isFalse);
      expect(p.touchPoiEnabled, isFalse);
      expect(p.initialTilt, 0);
    });
  });
}
