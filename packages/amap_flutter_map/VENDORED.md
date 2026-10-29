# Vendored: amap_flutter_map 3.0.0

来源：pub.dev 官方存档 `amap_flutter_map-3.0.0.tar.gz`（高德官方 Flutter 插件），
vendoring 进本仓库 `packages/` 以 path 依赖引用。`example/` 与上游自带
`test/`（用已废弃 API 的插件自测，主工程不需要）已删除。

换插件背景：原先使用的社区 fork `amap_map 1.0.15` 在一加 7 Pro / Android 10
上创建地图必崩（应用内面包屑实锤死在 TextureMapView 原生创建内部，Key、
签名、创建参数、Impeller 均已排除）。本包与官方 3.0.0 同为 TextureMapView，
故以下列补丁把渲染路径换成普通 MapView（SurfaceView 系）。

## 补丁清单（每处在代码里都有 `[vendored patch]` 注释）

1. **Android 视图类替换（核心补丁）**：
   - `android/.../AMapPlatformView.java`：字段与构造 `TextureMapView` → `MapView`
     （`new MapView(context, options)`）；两者生命周期方法
     （onCreate/onResume/onPause/onDestroy/onLowMemory/onSaveInstanceState）
     与 `getMap()` 一一对应，无其他改动。
   - `android/.../core/MapController.java`：字段/构造参数类型同步替换
     （仅用到 `getMap()`、`getWidth()`、`getHeight()`，MapView 都有）。
   - `overlays/AbstractOverlayController.java`、`overlays/marker/MarkersController.java`、
     `overlays/polyline/PolylinesController.java`：删除未实际使用的
     `TextureMapView` import。
2. **Dart 视图创建改混合合成**：
   `lib/src/core/method_channel_amap_flutter_map.dart` 的 `buildView` Android
   分支由 `AndroidView`（虚拟显示）改为 `PlatformViewLink` +
   `PlatformViewsService.initExpensiveAndroidView`（Hybrid Composition）。
   原因：SurfaceView 在虚拟显示模式下无法成像；iOS 分支保持 UiKitView 不变。
3. **hashValues → Object.hash**：`lib/src/types/` 下 camera.dart、marker.dart、
   marker_updates.dart、polygon_updates.dart、polyline_updates.dart、ui.dart
   共 8 处（`hashValues` 已被 Flutter 移除，是当年官方版在新 Flutter 下
   `flutter test` CFE 编译失败的原因）。
4. **Android 构建配置现代化**：`android/build.gradle` 镜像同源 fork
   amap_map 1.0.15 已在本工程 CI 验证的配置（namespace、compileSdk 35、
   mavenCentral），SDK 依赖由 `compileOnly com.amap.api:3dmap:8.1.0` 改为
   `implementation com.amap.api:3dmap-location-search:10.1.200_loc6.4.9_sea9.7.4`
   （与此前线上版本相同的原生 SDK 版本，保证运行时带 SDK 且行为一致）；
   `android/src/main/AndroidManifest.xml` 与 fork 对齐（namespace 模式）。
5. **iOS podspec**：`s.platform` 8.0 → 12.0（8.0 已被现行 Xcode/CocoaPods 拒绝）。
6. **pubspec**：对 `amap_flutter_base` 的依赖改为 path 依赖
   `../amap_flutter_base`（同仓 vendoring 版）；SDK 约束现代化为
   `>=3.0.0 <4.0.0`；加 `publish_to: none`。
7. **现行分析器机械修正**（不改行为）：5 处 `operator ==` 参数
   `dynamic` → `Object` 并补显式强转（本包 3 处：camera.dart、ui.dart ×2）；
   删 types.dart 里重复的 `export 'camera.dart'`、marker.dart 里重复的
   base_overlay 导入、camera.dart 里未使用的 cupertino 导入（均为原文存量
   问题）；`method_channel_amap_flutter_map.dart` 为混合合成补丁补
   `PlatformViewHitTestBehavior` 的显式导入（rendering.dart）。
8. **包级 analysis_options.yaml**：不套用主工程 flutter_lints 风格规则，
   包内忽略 `deprecated_member_use`（Color.value 序列化与原生协议对齐，
   不动）、`unnecessary_null_in_if_null_operators`、`unnecessary_import`
   三类存量 hint，使主工程 `flutter analyze` 保持零问题。

## 未改动的原有机制（与换插件决策相关）

- 运行时 Key/隐私注入走 AMapWidget 的 `apiKey` / `privacyStatement` 创建参数：
  Android 工厂 `AMapPlatformViewFactory.create()` 先
  `ConvertUtil.setPrivacyStatement(...)`（反射调 MapsInitializer 的
  updatePrivacyShow/updatePrivacyAgree）、再 `ConvertUtil.checkApiKey(...)`
  （MapsInitializer.setApiKey），最后才 `builder.build(...)` 构造平台视图
  （即 MapView），顺序满足「注入在建图之前」。
- `onMapCreated` 语义：平台视图创建完成后，Dart 侧经
  `AMapController.init` 等原生 `map#waitForMap`（AMap 就绪）后才回调，
  与旧 fork 一致，可作为「建图完成」面包屑落点。
