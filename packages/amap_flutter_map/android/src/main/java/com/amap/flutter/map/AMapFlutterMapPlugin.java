package com.amap.flutter.map;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * [vendored patch · 三期 iOS-only 桩化] 本插件自 2026-10-30 三期起
 * **仅 iOS 启用**：Android 侧的高德原生地图 GL 渲染器在目标机型上
 * 必崩（识途 v0.2.1–v0.2.6 实锤），安卓底图已改 Web 瓦片、永不
 * 创建本插件的平台视图。
 *
 * 因此 Android 实现整体桩化：保留插件类本体（GeneratedPluginRegistrant
 * 按 pubspec 的 pluginClass 引用它，类必须存在且可实例化），但
 * onAttachedToEngine **不注册任何视图工厂**；原实现文件（平台视图、
 * 控制器、叠加物、工具类）已全部删除，build.gradle 不再依赖
 * com.amap.api:3dmap，jniLibs 里的 libAMapSDK_MAP .so 已移除——
 * 安卓安装包里不会再出现任何高德地图原生库。iOS 侧实现原样保留。
 */
public class AMapFlutterMapPlugin implements FlutterPlugin {

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        // 桩实现：不注册视图工厂。Dart 侧在 Android 上不会构建
        // AMapWidget（AppMap 平台分流只在 iOS 选原生），即便误建，
        // 也只会得到「未注册视图类型」的框架错误而非原生崩溃。
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        // 无状态，无需清理。
    }
}
