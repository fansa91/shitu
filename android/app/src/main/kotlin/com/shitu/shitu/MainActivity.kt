package com.shitu.shitu

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {

    /// 高德定位桥（自持通道，生命周期跟 Activity，销毁时释放）。
    private var amapLocationBridge: AmapLocationBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        amapLocationBridge = AmapLocationBridge(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext,
        )
        // 运行时签名 SHA1 通道：设置页把实际安装包的签名证书 SHA1 显示出来，
        // 供用户与高德控制台登记的 SHA1 对照（不一致时 SDK 鉴权会失败）。
        // 返回原始小写 hex（无分隔符），格式化（大写+冒号）在 Dart 侧统一做。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.shitu.app/signature")
            .setMethodCallHandler { call, result ->
                if (call.method == "getSigningSha1Hex") {
                    try {
                        result.success(signingSha1Hex())
                    } catch (e: Exception) {
                        result.error("SIGNING_ERROR", e.message ?: "读取签名失败", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
        // 原生地图探针通道：Dart 侧设置页把用户自填的高德 Android SDK
        // Key 与当前定位（GCJ-02，可缺省）传进来，这里以 startActivity
        // 打开独立原生 Activity 承载 TextureMapView（绕开 Flutter
        // 平台视图嵌入层，见 NativeMapProbeActivity.kt 的背景说明）。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.shitu.app/native_map_probe")
            .setMethodCallHandler { call, result ->
                if (call.method == "openProbe") {
                    try {
                        val intent = Intent(this, NativeMapProbeActivity::class.java)
                        intent.putExtra(
                            NativeMapProbeActivity.EXTRA_API_KEY,
                            call.argument<String>("apiKey") ?: "",
                        )
                        call.argument<Double>("latitude")?.let {
                            intent.putExtra(NativeMapProbeActivity.EXTRA_LATITUDE, it)
                        }
                        call.argument<Double>("longitude")?.let {
                            intent.putExtra(NativeMapProbeActivity.EXTRA_LONGITUDE, it)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PROBE_OPEN", e.message ?: "打开探针页失败", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        amapLocationBridge?.dispose()
        amapLocationBridge = null
        super.onDestroy()
    }

    private fun signingSha1Hex(): String {
        val pm = packageManager
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            info.signingInfo?.apkContentsSigners ?: emptyArray()
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures
                ?: emptyArray()
        }
        val cert = signatures.firstOrNull()
            ?: throw IllegalStateException("未找到签名证书")
        val digest = MessageDigest.getInstance("SHA-1").digest(cert.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }
}
