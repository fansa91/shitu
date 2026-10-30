# Vendored: amap_flutter_map 3.0.0

来源：pub.dev 官方存档 `amap_flutter_map-3.0.0.tar.gz`（高德官方 Flutter 插件），
vendoring 进本仓库 `packages/` 以 path 依赖引用。`example/` 与上游自带
`test/`（用已废弃 API 的插件自测，主工程不需要）已删除。

换插件背景：原先使用的社区 fork `amap_map 1.0.15` 在一加 7 Pro / Android 10
上创建地图必崩（应用内面包屑实锤死在 TextureMapView 原生创建内部，Key、
签名、创建参数、Impeller 均已排除）。本包与官方 3.0.0 同为 TextureMapView，
故补丁 1 先把渲染路径换成普通 MapView（SurfaceView 系）二分；其后 SDK 又
降回 8.1.0（补丁 10）并加细粒度 Java 打点（补丁 11），v0.2.5 真机实测
MapView 创建链全程走通、进程改死在 onCreate 之后的渲染启动段，故补丁 12
把视图类换回 TextureMapView（TextureView 路径）继续二分该段。

## 补丁清单（每处在代码里都有 `[vendored patch]` 注释）

1. **Android 视图类替换（核心补丁；视图类部分已被补丁 12 反转，见下）**：
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
   mavenCentral），SDK 依赖由 `compileOnly` 改为 `implementation`
   （保证运行时带 SDK）；`android/src/main/AndroidManifest.xml` 与 fork
   对齐（namespace 模式）。SDK 具体版本几经变化：最初随 fork 用组合包
   10.1.200，后被第 10 条的版本二分取代。
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
9. **现行 Flutter 已移除 API 的 Java 适配**（v0.2.4 首轮 CI 编译实锤后补，
   写法镜像同源 fork amap_map 1.0.15 已验证版本）：
   - `AMapFlutterMapPlugin.java`：删 v1 嵌入
     `registerWith(PluginRegistry.Registrar)`（Registrar 已被移除；
     v2 `onAttachedToEngine` 已完整注册同一视图工厂，行为不变），
     连带删仅其使用的 `Activity`/`LifecycleOwner`/`PluginRegistry` 导入。
   - `utils/ConvertUtil.java`：`io.flutter.view.FlutterMain`（已移除）的
     静态 `getLookupKeyForAsset` 改用 `io.flutter.embedding.engine.loader.
     FlutterLoader` 实例；新增幂等 `ConvertUtil.initialize(Context)`，
     由 `AMapPlatformViewFactory.create()` 在建图前调用。
10. **原生 SDK 版本二分**（故障排查：所有真机失败构建的唯一共同因子是
    组合包 10.1.200，故换回官方原配版本线验证）：
    - 出处：pub 缓存 `amap_flutter_map-3.0.0/android/build.gradle` 的官方
      原始依赖行是 `compileOnly 'com.amap.api:3dmap:8.1.0'`——版本本身就
      是钉死的 8.1.0。本包改为 `implementation 'com.amap.api:3dmap:8.1.0'`
      （用 implementation 而非 compileOnly，是因为本插件必须自带 SDK
      运行时、宿主 App 不另行提供，属必要适配）。
    - 8.1.0 在 Maven Central 是 **jar 打包**（SHA-256
      `a8b1bbcd8ebdddd6ed3eb6167f1a4779f967ff71a8057582794a461d13010337`），
      jar 内含 classes 与 `lib/<abi>/libAMapSDK_MAP_v8_1_0.so`；Gradle 不会
      从普通 jar 依赖提取 .so，故把本工程实际出包的三个 ABI 的 .so 从该
      官方 jar **原样**提取到 `android/src/main/jniLibs/`：
      arm64-v8a `0c23055d7971c9424d0459fb0a7e6ac02745265e109e51ee4e226c197cce3550`、
      armeabi-v7a `a57ef473ecf413653e92117d478f309ad4037a28c8277691f719e62326a4faa7`、
      x86_64 `19194df0b00e6fc91b432ffcf8ad2c0c598e7611e90a022f37619f659026b5f1`
      （armeabi/x86 两个 ABI 本工程不出包，未提取）。
    - `android/build.gradle` 加 `useLibrary 'org.apache.http.legacy'`：
      8.1.0 的 mapcore 网络层引用 Apache HttpClient（该库自 Android 6 起
      移出 bootclasspath），高德当年官方接入文档即要求此声明。
    - API 兼容（已用官方 jar 实测核对）：`MapsInitializer.setApiKey`、
      反射用的 `updatePrivacyShow(Context, boolean, boolean)` /
      `updatePrivacyAgree(Context, boolean)`、`MapView(Context, AMapOptions)`
      与 `getMap()` 在 8.1.0 中均存在且签名一致，Java 调用零适配。
    - 已知残留观察：8.1.0 的个别 mapcore util 类引用
      `com.amap.api.location`（其内部 APS 定位路径）与
      `org.apache.http`（仅 1 个 util 类）；本工程不启用 SDK 定位
      （geolocator + 自绘标记），若真机命中 NoClassDefFoundError，
      第 11 条的 java_error 打点会把它直接报出来。
    - location/search 原生 SDK 未随本次引入（官方原配同样只有 3dmap；
      本工程搜索走 Web API）。
11. **Java 面包屑打点 + 异常可见**（与主工程 `MapCrashGuard` 联动）：
    - 新增 `utils/BreadcrumbUtil.java`：向应用支持目录的
      `amap_map_breadcrumbs.txt`（与 Dart 同一文件；path_provider 的
      getApplicationSupportDirectory 在 Android 上对应
      `Context.getFilesDir()`）追加写 `步骤名|毫秒时间戳`，写后立即
      flush/close；自身异常全吞，绝不影响建图。
    - 打点位置：`AMapPlatformViewFactory.create()` 在隐私注入后
      `java_privacy_done`、Key 注入后 `java_apikey_done`；
      `AMapPlatformView` 构造在 `new MapView` 前后
      `java_mapview_ctor_start` / `java_mapview_ctor_done`、`getMap()` 后
      `java_getmap_done`；生命周期 `onCreate` 完成 MapView.onCreate 后
      `java_oncreate_done`。
    - 异常可见：工厂 `create`、`AMapOptionsBuilder.build`、
      `AMapPlatformView` 构造与 `onCreate` 的 `catch (Throwable)` 在原有
      LogUtil 之外，再经 `BreadcrumbUtil.error` 写一行
      `java_error:<异常类简单名>`（只写类名——message 可能含 `|`/换行
      破坏行格式）。Dart 侧编解码已兼容 java_ 步骤与异常行，诊断展示为
      「原生：…」/「原生异常：<类名>」，自保判定不变、停留步自然落到
      最后一条 Java 子步骤/异常。

11. **R8 consumer 规则（v0.2.5 首轮 CI 修复）**：
    `android/consumer-rules.pro` + `defaultConfig.consumerProguardFiles`。
    首轮 CI 的 `:app:minifyReleaseWithR8` 以 Missing class 硬失败：
    8.1.0 的 mapcore util 引用 `com.amap.api.location.*`（定位 SDK），
    本工程有意不引入（定位走 geolocator），10.1.200 组合包自带这些类
    故旧构建不触发。规则仅一条 `-dontwarn com.amap.api.location.**`，
    让 R8 剥离对应代码路径；本工程不使用高德自带定位图层，无运行时影响。
12. **视图类换回 TextureMapView + 渲染段打点（v0.2.6）**：
    - 背景：v0.2.5（SDK 8.1.0 + 传统解压打包）真机：安装问题已由传统打包
      解决；Java 创建链全程走通（Key 注入→MapView 构造→getMap→onCreate
      完成、无 java_error），进程死在 onCreate 之后、Dart on_map_created
      之前的渲染启动段。MapView（SurfaceView）+混合合成这条路径此前从未
      被测到这一段，故换 TextureMapView（TextureView 路径）继续二分。
    - 视图类替换（反转补丁 1 的视图类部分，Dart 混合合成保持不动——
      TextureView 与混合合成兼容，避免同时改两个变量）：
      `AMapPlatformView` 字段/构造与 `core/MapController` 字段/构造参数
      类型 `MapView` → `TextureMapView`（`new TextureMapView(context,
      options)`；字段名沿用 `mapView`）。API 核验（对 8.1.0 官方 jar
      javap 实测）：TextureMapView 构造器 (Context)/(Context,
      AMapOptions)、`getMap()`、`onCreate/onResume/onPause/onDestroy/
      onSaveInstanceState/onLowMemory` 与 MapView 完全一致，零适配；
      jar 的 SHA-256 与第 10 条记录一致。
    - 渲染段面包屑（沿用 BreadcrumbUtil、同文件同格式，Dart 展示映射已
      在主工程 `map_crash_guard.dart` 补齐中文名）：
      - `java_ctor_done`：`AMapPlatformView` 构造器末尾（与
        `java_mapview_ctor_done` 仅 new 视图完成区分，中间隔着 getMap 与
        四个 controller 初始化）。视图构造的 wire 名沿用 `java_mapview_*`
        不改（历史落盘记录与 Dart 映射按此名识别）。
      - `java_onresume_start` / `java_onresume_done`：生命周期 onResume
        里夹住 `mapView.onResume()` 前后；该 catch 原先只记 LogUtil，
        本轮补齐 `BreadcrumbUtil.error` 异常可见（与 onCreate 一致）。
      - `java_map_loaded`：构造里经 `addOnMapLoadedListener` 附加的
        只打点监听触发时（MapController 自身亦以 add 注册，附加不冲突、
        不改既有就绪流程）。
      - `java_map_ready`：等价落点说明——8.1.0 的 `AMap` **没有**
        `getMapAsync` / `OnMapReadyCallback`（javap 实测无此方法/类），
        无法按新版 SDK 的回调打点；本 SDK 中「地图就绪」的原生信号即
        OnMapLoaded 到达 `MapController`（Dart `map#waitForMap` 正等在
        其 `mapReadyResult` 答复点），故在 `MapController.onMapLoaded()`
        答复 result 之前打 `java_map_ready`，语义等价。判读：死在渲染
        启动段时 `java_map_ready`/`java_map_loaded` 都不会出现，停留步
        落在 `java_onresume_done`（或更早）即为实锤。

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
