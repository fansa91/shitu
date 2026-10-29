import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/history_service.dart';
import 'services/map_crash_guard.dart';
import 'services/map_data_services.dart';
import 'services/places_service.dart';
import 'services/settings_service.dart';
import 'services/track_service.dart';
import 'theme/appearance.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsService();
  await settings.load();
  final places = PlacesService();
  await places.load();
  final tracks = TrackService();
  await tracks.load();
  final history = HistoryService();
  await history.load();
  // 读上一轮建图面包屑并判定自保：若上一轮死在建图过程中，
  // 本轮全应用回落示意地图（见 MapCrashGuard），打破崩溃循环。
  final crashGuard = await MapCrashGuard.loadDefault();
  runApp(ShituApp(
    settings: settings,
    places: places,
    tracks: tracks,
    history: history,
    crashGuard: crashGuard,
  ));
}

class ShituApp extends StatelessWidget {
  const ShituApp({
    super.key,
    required this.settings,
    required this.places,
    required this.tracks,
    required this.history,
    this.crashGuard,
  });

  final SettingsService settings;
  final PlacesService places;
  final TrackService tracks;
  final HistoryService history;

  /// 地图崩溃面包屑/自保（可选，测试可不传）。
  final MapCrashGuard? crashGuard;

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
                tracks: tracks,
                history: history,
                crashGuard: crashGuard,
              ),
            );
          },
        );
      },
    );
  }
}
