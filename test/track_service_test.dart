import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shitu/models/geo_point.dart';
import 'package:shitu/models/nav_track.dart';
import 'package:shitu/services/track_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('轨迹保存/读取往返与删除', () async {
    final service = TrackService();
    await service.load();
    expect(service.tracks, isEmpty);

    const track = NavTrack(
      id: 'track-1',
      name: '家 → 公司 · 10/29 08:30',
      originName: '家',
      destinationName: '公司',
      points: [
        GeoPoint(latitude: 22.54, longitude: 114.05),
        GeoPoint(latitude: 22.55, longitude: 114.06),
      ],
      distanceMeters: 2100,
      durationSeconds: 420,
      startedAtMs: 1761700000000,
    );
    await service.save(track);

    final reloaded = TrackService();
    await reloaded.load();
    expect(reloaded.tracks, hasLength(1));
    final got = reloaded.tracks.single;
    expect(got.name, track.name);
    expect(got.points, hasLength(2));
    expect(got.distanceMeters, 2100);

    await reloaded.remove('track-1');
    final again = TrackService();
    await again.load();
    expect(again.tracks, isEmpty);
  });
}
