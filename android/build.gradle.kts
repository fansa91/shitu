allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// amap_map 1.0.15 的 android/build.gradle 写死 compileSdkVersion 35，
// 而其传递依赖 flutter_plugin_android_lifecycle 2.0.35 的 AAR 元数据要求
// 消费方 compileSdk >= 36，release 构建会在 :amap_map:checkReleaseAarMetadata 失败。
// 这里统一把所有库子工程的 compileSdk 抬到 36（仅编译 API 层级，不动 target/minSdk）。
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.gradle.LibraryExtension) {
            if ((androidExt.compileSdk ?: 0) < 36) {
                androidExt.compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
