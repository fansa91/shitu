import 'package:flutter_test/flutter_test.dart';

import 'package:shitu/utils/format.dart';

void main() {
  group('formatDuration', () {
    test('不足 1 分钟显示秒', () {
      expect(formatDuration(45), '45 秒');
    });
    test('整分钟', () {
      expect(formatDuration(38 * 60), '38 分钟');
    });
    test('小时 + 分钟', () {
      expect(formatDuration(65 * 60), '1 小时 5 分钟');
    });
    test('整小时省略分钟', () {
      expect(formatDuration(2 * 3600), '2 小时');
    });
  });

  group('formatDistance', () {
    test('不足 1 km 显示米', () {
      expect(formatDistance(850), '850 米');
    });
    test('km 保留一位小数', () {
      expect(formatDistance(12400), '12.4 km');
    });
    test('整公里', () {
      expect(formatDistance(3000), '3.0 km');
    });
  });

  group('formatClock', () {
    test('补零格式 HH:mm', () {
      expect(formatClock(DateTime(2026, 10, 29, 18, 42)), '18:42');
      expect(formatClock(DateTime(2026, 10, 29, 9, 5)), '09:05');
    });
  });
}
