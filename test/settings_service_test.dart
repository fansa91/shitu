import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shitu/models/map_provider.dart';
import 'package:shitu/services/settings_service.dart';
import 'package:shitu/theme/appearance.dart';

import 'secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installSecureStorageMock(); // Key 已迁安全存储，通道用内存 mock
  });

  test('默认值：高德 + 系统语音 + 预合成开 + 无 Key', () async {
    final service = SettingsService();
    await service.load();
    expect(service.provider, MapProvider.amap);
    expect(service.ttsEngine, TtsEngine.system);
    expect(service.ttsPresynthesize, isTrue);
    expect(service.hasAnyKey, isFalse);
  });

  test('Key / 服务商 / TTS 偏好存取往返', () async {
    final service = SettingsService();
    await service.load();
    await service.setKeyFor(MapProvider.amap, ' amap-key-123456 ');
    await service.setKeyFor(MapProvider.baidu, 'baidu-ak-123456');
    await service.setNvidiaKey('nvapi-test-123456');
    await service.setProvider(MapProvider.tencent);
    await service.setTtsEngine(TtsEngine.nvidia);
    await service.setTtsPresynthesize(false);

    // 新实例从持久化层重新读出，验证往返一致（Key 会被 trim）。
    final reloaded = SettingsService();
    await reloaded.load();
    expect(reloaded.keyFor(MapProvider.amap), 'amap-key-123456');
    expect(reloaded.keyFor(MapProvider.baidu), 'baidu-ak-123456');
    expect(reloaded.keyFor(MapProvider.tencent), isEmpty);
    expect(reloaded.hasAnyKey, isTrue);
    expect(reloaded.hasKeyFor(MapProvider.tencent), isFalse);
    expect(reloaded.nvidiaKey, 'nvapi-test-123456');
    expect(reloaded.provider, MapProvider.tencent);
    expect(reloaded.ttsEngine, TtsEngine.nvidia);
    expect(reloaded.ttsPresynthesize, isFalse);
  });

  test('外观偏好：默认值与存取往返', () async {
    final service = SettingsService();
    await service.load();
    // 默认：跟随系统 + 动态取色开 + 品牌蓝种子色。
    expect(service.themeMode, AppThemeMode.system);
    expect(service.dynamicColorEnabled, isTrue);
    expect(service.seedColor, brandSeedColor);

    await service.setThemeMode(AppThemeMode.dark);
    await service.setDynamicColorEnabled(false);
    await service.setSeedColor(const Color(0xFFC62828));

    final reloaded = SettingsService();
    await reloaded.load();
    expect(reloaded.themeMode, AppThemeMode.dark);
    expect(reloaded.dynamicColorEnabled, isFalse);
    expect(reloaded.seedColor, const Color(0xFFC62828));
    expect(reloaded.seedColorValue, 0xFFC62828);
  });
}
