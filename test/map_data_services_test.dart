import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shitu/models/map_provider.dart';
import 'package:shitu/services/amap_web_service.dart';
import 'package:shitu/services/map_data_service.dart';
import 'package:shitu/services/map_data_services.dart';
import 'package:shitu/services/settings_service.dart';

import 'secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock(); // Key 已迁安全存储
  });

  group('服务工厂回退逻辑', () {
    test('无 Key → SampleMapDataService 且标注示例', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();
      final services = MapDataServices(settings);
      expect(services.isSampleFor(MapProvider.amap), isTrue);
      expect(services.serviceFor(MapProvider.amap),
          isA<SampleMapDataService>());
      expect(services.serviceFor(MapProvider.amap).isSample, isTrue);
    });

    test('填 Key 后 → 真实服务（不发请求，仅类型判断）', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();
      await settings.setKeyFor(MapProvider.amap, 'web-key-for-test-only');
      final services = MapDataServices(settings);
      expect(services.isSampleFor(MapProvider.amap), isFalse);
      expect(services.serviceFor(MapProvider.amap), isA<AmapWebService>());
      expect(services.serviceFor(MapProvider.amap).isSample, isFalse);
      // 未填 Key 的服务商仍回退示例
      expect(services.isSampleFor(MapProvider.baidu), isTrue);
    });
  });

  group('设置新增字段持久化', () {
    test('高德 SDK 双 Key 与隐私同意往返', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.load();
      expect(settings.privacyAgreed, isFalse);
      await settings.setAmapSdkKeys(
        androidKey: ' android-sdk-key ',
        iosKey: 'ios-sdk-key',
      );
      await settings.setPrivacyAgreed(true);
      expect(settings.amapSdkAndroidKey, 'android-sdk-key'); // 已 trim
      expect(settings.amapSdkIosKey, 'ios-sdk-key');
      expect(settings.hasAmapSdkAndroidKey, isTrue);

      final reloaded = SettingsService();
      await reloaded.load();
      expect(reloaded.amapSdkAndroidKey, 'android-sdk-key');
      expect(reloaded.amapSdkIosKey, 'ios-sdk-key');
      expect(reloaded.privacyAgreed, isTrue);
    });
  });
}
