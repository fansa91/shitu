import 'package:flutter_test/flutter_test.dart';
import 'package:shitu/models/map_provider.dart';
import 'package:shitu/utils/external_link.dart';

void main() {
  group('KeyConsoleUrls', () {
    test('四个控制台地址都是合法的 https 地址且与约定一致', () {
      const expected = {
        KeyConsoleUrls.amap: 'https://console.amap.com/dev/key/app',
        KeyConsoleUrls.baidu: 'https://lbsyun.baidu.com/apiconsole/key#/home',
        KeyConsoleUrls.tencent:
            'https://lbs.qq.com/dev/console/application/mine',
        KeyConsoleUrls.nvidia: 'https://build.nvidia.com/settings/api-keys',
      };
      expected.forEach((actual, want) {
        expect(actual, want);
        final uri = Uri.parse(actual);
        expect(uri.scheme, 'https');
        expect(uri.host, isNotEmpty);
      });
    });

    test('forProvider 按服务商返回对应地址', () {
      expect(KeyConsoleUrls.forProvider(MapProvider.amap),
          KeyConsoleUrls.amap);
      expect(KeyConsoleUrls.forProvider(MapProvider.baidu),
          KeyConsoleUrls.baidu);
      expect(KeyConsoleUrls.forProvider(MapProvider.tencent),
          KeyConsoleUrls.tencent);
    });
  });
}
