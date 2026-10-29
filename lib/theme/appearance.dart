import 'package:flutter/material.dart';

/// 主题模式（应用自有枚举，落盘存 name，main.dart 再映射为 ThemeMode）。
enum AppThemeMode { system, light, dark }

extension AppThemeModeX on AppThemeMode {
  ThemeMode get materialMode => switch (this) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  String get label => switch (this) {
        AppThemeMode.system => '跟随系统',
        AppThemeMode.light => '浅色',
        AppThemeMode.dark => '深色',
      };
}

/// 识途品牌主色（地图蓝）：默认种子色，也是无动态取色时的回落色。
const brandSeedColor = Color(0xFF1A73E8);

/// 主题种子色预设：选中后由 ColorScheme.fromSeed 生成整套 M3 配色。
class SeedOption {
  const SeedOption(this.name, this.color);

  final String name;
  final Color color;
}

const seedOptions = <SeedOption>[
  SeedOption('品牌蓝', brandSeedColor),
  SeedOption('青碧', Color(0xFF00796B)),
  SeedOption('森绿', Color(0xFF388E3C)),
  SeedOption('橙阳', Color(0xFFEF6C00)),
  SeedOption('紫罗', Color(0xFF7B1FA2)),
  SeedOption('朱红', Color(0xFFC62828)),
  SeedOption('玫红', Color(0xFFAD1457)),
];
