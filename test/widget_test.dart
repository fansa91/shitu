import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shitu/main.dart';
import 'package:shitu/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('主页渲染搜索栏、数据源芯片与底部面板快捷入口',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.load();

    await tester.pumpWidget(ShituApp(settings: settings));
    await tester.pump();

    // 悬浮搜索栏
    expect(find.text('搜索地点 / 地址'), findsOneWidget);
    // 数据源芯片（默认高德）
    expect(find.text('高德地图 ▾'), findsOneWidget);
    // 底部面板快捷入口
    expect(find.text('家'), findsOneWidget);
    expect(find.text('公司'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    // 无 Key 时显示引导卡
    expect(find.text('还没有填写任何 Key'), findsOneWidget);
  });
}
