import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/history_service.dart';
import 'services/location_guard.dart';
import 'services/map_data_services.dart';
import 'services/places_service.dart';
import 'services/settings_service.dart';
import 'services/track_service.dart';
import 'theme/appearance.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsService();
  await settings.load();
  // 高德定位崩溃守卫结算：上次启动若在高德定位过程中进程消失
  // （「进行中」标记残留），本次跳闸、自动改用系统定位（见
  // location_guard.dart），避免原生硬崩连环。
  await AmapLocationGuard().settleOnLaunch();
  final places = PlacesService();
  await places.load();
  final tracks = TrackService();
  await tracks.load();
  final history = HistoryService();
  await history.load();
  runApp(
    ShituApp(
      settings: settings,
      places: places,
      tracks: tracks,
      history: history,
    ),
  );
}

class ShituApp extends StatelessWidget {
  const ShituApp({
    super.key,
    required this.settings,
    required this.places,
    required this.tracks,
    required this.history,
  });

  final SettingsService settings;
  final PlacesService places;
  final TrackService tracks;
  final HistoryService history;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            final useDynamic = settings.dynamicColorEnabled;
            final lightScheme =
                (useDynamic ? lightDynamic : null) ??
                ColorScheme.fromSeed(seedColor: settings.seedColor);
            final darkScheme =
                (useDynamic ? darkDynamic : null) ??
                ColorScheme.fromSeed(
                  seedColor: settings.seedColor,
                  brightness: Brightness.dark,
                );
            return MaterialApp(
              title: '识途',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(colorScheme: lightScheme, useMaterial3: true),
              darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
              themeMode: settings.themeMode.materialMode,
              home: HomeScreen(
                settings: settings,
                services: MapDataServices(settings),
                places: places,
                tracks: tracks,
                history: history,
              ),
            );
          },
        );
      },
    );
  }
}
