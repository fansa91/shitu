import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/map_data_services.dart';
import 'services/places_service.dart';
import 'services/settings_service.dart';
import 'theme/appearance.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsService();
  await settings.load();
  final places = PlacesService();
  await places.load();
  runApp(ShituApp(settings: settings, places: places));
}

class ShituApp extends StatelessWidget {
  const ShituApp({super.key, required this.settings, required this.places});

  final SettingsService settings;
  final PlacesService places;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            final useDynamic = settings.dynamicColorEnabled;
            final lightScheme = (useDynamic ? lightDynamic : null) ??
                ColorScheme.fromSeed(seedColor: settings.seedColor);
            final darkScheme = (useDynamic ? darkDynamic : null) ??
                ColorScheme.fromSeed(
                  seedColor: settings.seedColor,
                  brightness: Brightness.dark,
                );
            return MaterialApp(
              title: '识途',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(colorScheme: lightScheme, useMaterial3: true),
              darkTheme:
                  ThemeData(colorScheme: darkScheme, useMaterial3: true),
              themeMode: settings.themeMode.materialMode,
              home: HomeScreen(
                settings: settings,
                services: MapDataServices(settings),
                places: places,
              ),
            );
          },
        );
      },
    );
  }
}
