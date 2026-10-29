import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shitu/models/map_provider.dart';
import 'package:shitu/services/settings_service.dart';

import 'secure_storage_mock.dart';

// Key 迁移测试：旧版 SharedPreferences 明文 → flutter_secure_storage。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('旧明文 Key 在 load 时迁入安全存储并删除明文', () async {
    SharedPreferences.setMockInitialValues({
      'key_amap': 'legacy-amap-key',
      'key_nvidia': 'legacy-nvapi-key',
      'amap_sdk_android_key': 'legacy-sdk-key',
      'provider': 'baidu', // 非敏感设置不受迁移影响
    });
    final secure = installSecureStorageMock();

    final service = SettingsService();
    await service.load();

    expect(service.keyFor(MapProvider.amap), 'legacy-amap-key');
    expect(service.nvidiaKey, 'legacy-nvapi-key');
    expect(service.amapSdkAndroidKey, 'legacy-sdk-key');
    expect(service.provider, MapProvider.baidu);

    // 已搬进安全存储
    expect(secure['key_amap'], 'legacy-amap-key');
    expect(secure['key_nvidia'], 'legacy-nvapi-key');
    expect(secure['amap_sdk_android_key'], 'legacy-sdk-key');

    // 旧明文已删除，非敏感项保留
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('key_amap'), isNull);
    expect(prefs.getString('key_nvidia'), isNull);
    expect(prefs.getString('amap_sdk_android_key'), isNull);
    expect(prefs.getString('provider'), 'baidu');
  });

  test('安全存储已有值时优先它，并清掉残留明文', () async {
    SharedPreferences.setMockInitialValues({'key_amap': 'stale-plain-key'});
    final secure = installSecureStorageMock();
    secure['key_amap'] = 'secure-key';

    final service = SettingsService();
    await service.load();

    expect(service.keyFor(MapProvider.amap), 'secure-key');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('key_amap'), isNull);
  });

  test('新写入的 Key 只进安全存储，prefs 无明文', () async {
    SharedPreferences.setMockInitialValues({});
    final secure = installSecureStorageMock();

    final service = SettingsService();
    await service.load();
    await service.setKeyFor(MapProvider.tencent, 'tencent-key-1');
    await service.setAmapSdkKeys(androidKey: 'sdk-a', iosKey: 'sdk-i');

    expect(secure['key_tencent'], 'tencent-key-1');
    expect(secure['amap_sdk_android_key'], 'sdk-a');
    expect(secure['amap_sdk_ios_key'], 'sdk-i');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('key_tencent'), isNull);
    expect(prefs.getString('amap_sdk_android_key'), isNull);
  });
}
