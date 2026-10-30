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
    // 高德组合包（地图 10.1.600 + 定位 6.5.1 + 搜索 9.7.4）：一包同时供
    // ① 二期的定位桥（AmapLocationBridge.kt）与 ② 原生地图探针
    // （NativeMapProbeActivity.kt）。
    //
    // 为什么不再单独依赖 com.amap.api:location:6.5.1（选型已实测核查）：
    // - 任何 3dmap 工件（独立版 10.0.600 与组合包都一样）的 jar 内都自带
    //   com.amap.api.location 的 24 个门面类，与 location:6.5.1 jar 里的
    //   同名类必然 dex 重复类冲突，二者不可共存；
    // - 组合包内的定位门面是自包含实现（内部走 com.amap.api.col.3sl +
    //   com.autonavi.aps，均在本 jar 内；独立 location 包则走 com.loc），
    //   且其定位版本恰为 6.5.1，与桥原依赖同版；
    // - 桥用到的 API 已逐项用 javap 对组合包 jar 核实：静态
    //   updatePrivacyShow/updatePrivacyAgree/setApiKey、构造、监听、
    //   Option 的 setGpsFirst/setOffset/setHttpTimeOut 等签名全一致。
    // 故移除独立 location 依赖、改由组合包统一提供，桥代码零改动。
    //
    // 原生库：jar 内的 libAMapSDK_MAP_v10_1_600.so 已手动提取到
    // src/main/jniLibs/{arm64-v8a,armeabi-v7a}（jar 依赖不会被 AGP
    // 自动解出 .so，与当年 vendored 插件提取 8.1.0 的做法相同）。
    // 组合包仅含这两个 ABI 的 .so。
    implementation("com.amap.api:3dmap-location-search:10.1.600_loc6.5.1_sea9.7.4")
}
