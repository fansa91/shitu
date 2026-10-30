import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 自签 release：CI 会在 android/key.properties 里写入 keystore 信息；
// 本地没有该文件时回退到 debug 签名，保证 flutter run --release 照常可用。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.shitu.shitu"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.shitu.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }


    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // 本地没有 key.properties 时用 debug key，保证 flutter run --release 可用
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 高德导航 SDK 合包 9.8.3（flavor map3dnavisearchloc：导航 9.8.3 +
    // 地图 9.8.3 + 定位 6.4.2 + 搜索）：一包同时供 ① 二期的定位桥
    // （AmapLocationBridge.kt）与 ② 原生地图探针二号
    // （NativeMapProbeActivity.kt）。
    //
    // 为什么是本地 jar 而不是 Maven 坐标（2026-10-30 实查）：
    // - 导航合包在 Maven Central 的工件 com.amap.api:
    //   navi-3dmap-location-search 最早只有 10.0.700 起，**没有 9.8.3**
    //   （官方下载页也只给最新版），无法用坐标引入；
    // - 本 jar 是从用户提供的 bmap（me.gfuil.bmap）APK 的 dex 还原的
    //   高德类集合——与「在用户一加 7 Pro 上实测能正常开图」的那份
    //   二进制逐字节同源（.so 的 sha256 见 jniLibs 说明），只保留
    //   com.amap.api.* 与 com.autonavi.* 两棵包树（2250 个类），
    //   bmap 自身与百度/腾讯的类一概不带；
    // - 实验变量：地图 SDK 线（10.1.200/10.1.600/8.1.0）在该机上
    //   Flutter 嵌入与原生直挂两种承载全灭，导航线的渲染二进制
    //   （libAMapSDK_NAVI_v9_8_3.so）是唯一没试过且有同机存活样本的。
    //
    // 定位桥复核（javap 对本 jar 逐项核对）：合包自带定位版本为
    // **6.4.2**（AMapLocationClient.getVersion() 常量实测；一号探针的
    // 地图组合包是 6.5.1）。桥用到的静态三件套、构造、监听、Option 的
    // setGpsFirst/setGpsFirstTimeout(long)/setOffset/setOnceLocation
    // Latest/setHttpTimeOut(long)/setInterval(long)、AMapLocation 全部
    // getter 签名齐备，桥代码零改动、功能不降级（版本差仅在 SDK 内部
    // 实现，桥的 API 面 6.4.2 已全覆盖）。
    //
    // 原生库与资源（均与 bmap 的 APK 内配置对齐）：
    // - libAMapSDK_NAVI_v9_8_3.so 提取到 src/main/jniLibs/arm64-v8a
    //   （sha256 883ce2ec…b30494；ELF LOAD 对齐实测 0x1000，无需
    //   useLegacyPackaging）。导航包只有 arm64 版 .so（bmap 本人亦然），
    //   armeabi-v7a/x86_64 包无此库——那两个 ABI 上定位（纯 Java）照常、
    //   探针页打不开，属实验预期；
    // - SDK 运行时 assets（map_assets/、ae/、amap_sdk_*、SDK_* 等）
    //   已提取到 src/main/assets/，与 bmap 的合并 assets 一致。
    implementation(files("libs/amap-navi-sdk-9.8.3.jar"))
}
