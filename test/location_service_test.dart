import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:shitu/models/geo_point.dart';
import 'package:shitu/models/located_fix.dart';
import 'package:shitu/services/location_runtime_status.dart';
import 'package:shitu/services/location_service.dart';
import 'package:shitu/utils/coord.dart';

Position _position(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026, 10, 29),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

LocationService _service({
  bool serviceEnabled = true,
  LocationPermission permission = LocationPermission.whileInUse,
  LocationPermission afterRequest = LocationPermission.whileInUse,
  Future<Position> Function()? fetch,
}) {
  return LocationService(
    isServiceEnabled: () async => serviceEnabled,
    checkPermission: () async => permission,
    requestPermission: () async => afterRequest,
    fetchPosition: fetch ?? () async => _position(39.9042, 116.4074),
    positionStream: () => const Stream.empty(),
  );
}

void main() {
  group('FollowLock 跟随状态机', () {
    test('锁定 → 拖图解锁 → 再锁定', () {
      final lock = FollowLock();
      expect(lock.following, isFalse);
      lock.lock();
      expect(lock.following, isTrue);
      lock.unlockByUserGesture();
      expect(lock.following, isFalse);
      lock.lock();
      expect(lock.following, isTrue);
      lock.unlock();
      expect(lock.following, isFalse);
    });
  });

  group('LocationService', () {
    test('定位服务未开 → serviceDisabled 中文提示', () async {
      final service = _service(serviceEnabled: false);
      await expectLater(
        service.currentLocation(),
        throwsA(isA<LocationException>()
            .having((e) => e.kind, 'kind', LocationErrorKind.serviceDisabled)
            .having((e) => e.needsSettings, 'needsSettings', isTrue)),
      );
    });

    test('权限被拒（可再请求）→ permissionDenied', () async {
      final service = _service(
        permission: LocationPermission.denied,
        afterRequest: LocationPermission.denied,
      );
      await expectLater(
        service.currentLocation(),
        throwsA(isA<LocationException>().having(
            (e) => e.kind, 'kind', LocationErrorKind.permissionDenied)),
      );
    });

    test('权限永久拒绝 → permissionDeniedForever 且引导去设置', () async {
      final service = _service(permission: LocationPermission.deniedForever);
      await expectLater(
        service.currentLocation(),
        throwsA(isA<LocationException>()
            .having((e) => e.kind, 'kind',
                LocationErrorKind.permissionDeniedForever)
            .having((e) => e.needsSettings, 'needsSettings', isTrue)),
      );
    });

    test('首次拒绝后请求成功 → 正常返回', () async {
      final service = _service(
        permission: LocationPermission.denied,
        afterRequest: LocationPermission.whileInUse,
      );
      final point = await service.currentLocation();
      expect(point.latitude, isNot(39.9042)); // 已转 GCJ-02
    });

    test('WGS-84 坐标进 App 前转 GCJ-02', () async {
      final service = _service();
      final point = await service.currentLocation();
      final expected =
          wgs84ToGcj02(const GeoPoint(latitude: 39.9042, longitude: 116.4074));
      expect(point.latitude, closeTo(expected.latitude, 1e-9));
      expect(point.longitude, closeTo(expected.longitude, 1e-9));
    });

    test('系统结果带精度/方向，并写入运行时状态（设置页精度行）', () async {
      final status = LocationRuntimeStatus();
      final service = LocationService(
        status: status,
        isServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        requestPermission: () async => LocationPermission.whileInUse,
        fetchPosition: () async => Position(
          latitude: 39.9042,
          longitude: 116.4074,
          timestamp: DateTime(2026, 10, 29),
          accuracy: 7.5,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 200,
          headingAccuracy: 0,
          speed: 3,
          speedAccuracy: 0,
        ),
        positionStream: () => const Stream.empty(),
      );
      final fix = await service.currentFix();
      expect(fix.accuracyMeters, 7.5);
      expect(fix.bearingDegrees, 200);
      expect(status.lastAccuracyMeters, 7.5);
      expect(status.lastFixSource, LocationSource.system);
      expect(status.activeSource, LocationSource.system);
    });

    test('取位置超时 → timeout 中文提示', () async {
      final service = _service(
        fetch: () async => throw TimeoutException('gps timeout'),
      );
      await expectLater(
        service.currentLocation(),
        throwsA(isA<LocationException>()
            .having((e) => e.kind, 'kind', LocationErrorKind.timeout)),
      );
    });
  });
}
