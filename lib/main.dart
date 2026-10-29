import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/map_data_services.dart';
import 'services/settings_service.dart';

/// 识途品牌主色（地图蓝），无动态取色时回落使用。
const _brandSeed = Color(0xFF1A73E8);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsService();
  await settings.load();
  runApp(ShituApp(settings: settings));
}

class ShituApp extends StatelessWidget {
  const ShituApp({super.key, required this.settings});

  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final lightScheme = lightDynamic ??
            ColorScheme.fromSeed(seedColor: _brandSeed);
        final darkScheme = darkDynamic ??
            ColorScheme.fromSeed(
              seedColor: _brandSeed,
              brightness: Brightness.dark,
            );
        return MaterialApp(
          title: '识途',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorScheme: lightScheme, useMaterial3: true),
          darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
          home: HomeScreen(
            settings: settings,
            services: MapDataServices(settings),
          ),
        );
      },
    );
  }
}
