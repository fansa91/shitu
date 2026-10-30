import 'package:flutter_test/flutter_test.dart';
import 'package:shitu/services/map_backend.dart';

void main() {
  group('selectMapBackend 地图后端选择', () {
    test('iOS + 已同意隐私 + 已填 iOS Key → 原生高德', () {
      expect(
        selectMapBackend(
          isIOS: true,
          privacyAgreed: true,
          iosKey: 'ios-key-123',
        ),
        MapBackend.nativeAmap,
      );
    });

    test('iOS 无 Key / 未同意隐私 → 回落瓦片（不回示意图）', () {
      expect(
        selectMapBackend(isIOS: true, privacyAgreed: true, iosKey: ''),
        MapBackend.tiles,
      );
      expect(
        selectMapBackend(isIOS: true, privacyAgreed: false, iosKey: 'k'),
        MapBackend.tiles,
      );
      // 纯空白 Key 视为未填。
      expect(
        selectMapBackend(isIOS: true, privacyAgreed: true, iosKey: '   '),
        MapBackend.tiles,
      );
    });

    test('Android 条件全齐也恒瓦片（原生 GL 必崩 + 插件已桩化）', () {
      expect(
        selectMapBackend(isIOS: false, privacyAgreed: true, iosKey: 'k'),
        MapBackend.tiles,
      );
    });

    test('桌面端恒瓦片', () {
      expect(
        selectMapBackend(isIOS: false, privacyAgreed: false, iosKey: ''),
        MapBackend.tiles,
      );
    });
  });
}
