> **已停用（2026-10-30）**：识途底图已切换为 flutter_map + 高德 Web 瓦片（见 lib/widgets/tile_map_view.dart 与 lib/services/map_tiles.dart），本 vendored 插件自此不再被 pubspec 引用，保留在仓内仅作历史留档，勿再基于它开发。

# Vendored: amap_flutter_base 3.0.0

来源：pub.dev 官方存档 `amap_flutter_base-3.0.0.tar.gz`（高德官方基础库，
纯 Dart，无原生代码），vendoring 进本仓库 `packages/` 以 path 依赖引用，
供同仓 `packages/amap_flutter_map` 与主应用使用。

## 补丁清单（每处在代码里都有 `[vendored patch]` 注释）

- **hashValues → Object.hash**（`hashValues` 已被 Flutter 移除，是官方
  3.0.0 在 Flutter 3.47 / Dart 3.13 下 `flutter test` CFE 编译失败的原因）：
  - `lib/amap_flutter_base.dart`：从 `dart:ui` 的 show 列表移除 `hashValues`；
  - `lib/src/amap_api_key.dart`：`AMapApiKey.hashCode`；
  - `lib/src/amap_privacy_statement.dart`：`AMapPrivacyStatement.hashCode`；
  - `lib/src/location.dart`：3 处（AMapLocation / LatLng / LatLngBounds）。

- **现行分析器机械修正**（不改行为）：2 处 `operator ==` 参数
  `dynamic` → `Object` 并补显式强转（amap_api_key.dart、
  amap_privacy_statement.dart）。
- **pubspec**：SDK 约束现代化为 `>=3.0.0 <4.0.0`；加 `publish_to: none`。
- **包级 analysis_options.yaml**：不套用主工程 flutter_lints，包内忽略
  存量 hint，使主工程 `flutter analyze` 保持零问题。

其余文件与官方 3.0.0 原样一致。
