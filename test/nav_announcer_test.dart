import 'package:flutter_test/flutter_test.dart';

import 'package:shitu/models/map_provider.dart';
import 'package:shitu/services/nav_announcer.dart';

void main() {
  group('announcementThresholdsFor 阈值按出行方式', () {
    test('驾车与公交同组：300/100/30', () {
      for (final mode in [TransportMode.driving, TransportMode.transit]) {
        final t = announcementThresholdsFor(mode);
        expect(t.previewMeters, 300, reason: '$mode');
        expect(t.prepareMeters, 100, reason: '$mode');
        expect(t.executeMeters, 30, reason: '$mode');
      }
    });

    test('步行与骑行同组：60/25/10', () {
      for (final mode in [TransportMode.walking, TransportMode.cycling]) {
        final t = announcementThresholdsFor(mode);
        expect(t.previewMeters, 60, reason: '$mode');
        expect(t.prepareMeters, 25, reason: '$mode');
        expect(t.executeMeters, 10, reason: '$mode');
      }
    });
  });

  group('ManeuverAnnouncer 门控状态机（驾车阈值）', () {
    late ManeuverAnnouncer announcer;

    setUp(() {
      announcer = ManeuverAnnouncer(
        announcementThresholdsFor(TransportMode.driving),
      );
    });

    String? feed(int idx, double meters, [String text = '左转进入中山路']) =>
        announcer.advance(
          maneuverIndex: idx,
          distanceToManeuverMeters: meters,
          instruction: text,
        );

    test('阈值外不播；进入后三段递进、各只播一次', () {
      expect(feed(0, 800), isNull);
      expect(feed(0, 301), isNull);
      expect(feed(0, 300), '前方 300 米，左转进入中山路');
      // 同段内继续接近不重复播报。
      expect(feed(0, 250), isNull);
      expect(feed(0, 120), isNull);
      expect(feed(0, 100), '前方 100 米，左转进入中山路');
      expect(feed(0, 60), isNull);
      expect(feed(0, 30), '前方 30 米，左转进入中山路');
      expect(feed(0, 10), isNull);
    });

    test('未越过前一机动点不播下一：下标不变时只服务当前机动点', () {
      // 当前机动点 0 全程走完三段。
      expect(feed(0, 250), isNotNull);
      expect(feed(0, 90), isNotNull);
      expect(feed(0, 20), isNotNull);
      // 仍在机动点 0（未越过）：喂任何距离都不产生机动点 1 的文案。
      expect(feed(0, 5, '右转进入人民路'), isNull);
      // 越过（下标变 1）才解锁：阈值外先不播，进圈才播它自己的预告。
      expect(feed(1, 1200, '右转进入人民路'), isNull);
      expect(feed(1, 280, '右转进入人民路'), '前方 300 米，右转进入人民路');
    });

    test('跨级到达只播最紧迫一段，早段静默消费、不回补', () {
      // 一帧从 400 米跳到 20 米（定位稀疏/隧道出来）：只播执行段。
      expect(feed(0, 400), isNull);
      expect(feed(0, 20), '前方 30 米，左转进入中山路');
      // 距离回涨到准备段也不回补「前方 100 米」。
      expect(feed(0, 90), isNull);
      expect(feed(0, 250), isNull);
    });

    test('reset 后同一机动点可重新播报（重规划换路线用）', () {
      expect(feed(0, 250), isNotNull);
      announcer.reset();
      expect(announcer.maneuverIndex, -1);
      expect(feed(0, 250), '前方 300 米，左转进入中山路');
    });
  });

  group('ManeuverAnnouncer（步行阈值）', () {
    test('60/25/10 三段文案取命中阶段阈值', () {
      final announcer = ManeuverAnnouncer(
        announcementThresholdsFor(TransportMode.walking),
      );
      String? feed(double m) => announcer.advance(
            maneuverIndex: 0,
            distanceToManeuverMeters: m,
            instruction: '左转进入中山路',
          );
      expect(feed(80), isNull);
      expect(feed(55), '前方 60 米，左转进入中山路');
      expect(feed(20), '前方 25 米，左转进入中山路');
      expect(feed(8), '前方 10 米，左转进入中山路');
      expect(feed(3), isNull);
    });
  });
}
