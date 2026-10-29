package com.shitu.shitu

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
