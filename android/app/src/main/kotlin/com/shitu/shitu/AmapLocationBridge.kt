package com.shitu.shitu

import android.content.Context
import com.amap.api.location.AMapLocation
import com.amap.api.location.AMapLocationClient
import com.amap.api.location.AMapLocationClientOption
import com.amap.api.location.AMapLocationListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * 高德定位 SDK（com.amap.api:location:6.5.1）的最小原生桥：
 * Dart 侧 lib/services/amap_location.dart 经 MethodChannel
 * （com.shitu.app/amap_location）+ EventChannel
 * （com.shitu.app/amap_location_stream）调用。
 *
 * 面只有五件事：隐私声明、setApiKey、单次定位、持续定位、停止。
 * 坐标是高德原生 GCJ-02，桥原样透传，Dart 侧禁止再转换。
 *
 * 注意：本文件在本机无 Android SDK 未经编译，首编译在 CI 出包
 * 轮次；写时已按 6.5.1 的公开 API 逐项核对方法签名。
 */
class AmapLocationBridge(messenger: BinaryMessenger, private val appContext: Context) {

    private var client: AMapLocationClient? = null
    private var pendingOnce: MethodChannel.Result? = null
    private var eventSink: EventChannel.EventSink? = null
    private var watching = false

    private val listener = AMapLocationListener { location ->
        if (location == null) return@AMapLocationListener
        val payload = location.toPayload()
        val once = pendingOnce
        when {
            once != null -> {
                pendingOnce = null
                // 失败也走 success + errorCode 字段：Dart 侧 parseAmapFix
                // 统一判错，能拿回原生错误码（如 7=Key 鉴权失败）。
                once.success(payload)
                if (!watching) client?.stopLocation()
            }
            watching -> eventSink?.success(payload)
            else -> Unit
        }
    }

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> initClient(call.argument<String>("apiKey") ?: "", result)
                "fetchOnce" -> fetchOnce(result)
                "stopWatch" -> {
                    stopWatch()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    startWatch()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    stopWatch()
                }
            },
        )
    }

    /** 隐私声明必须在构造 AMapLocationClient 之前（SDK 6.x 强制）。 */
    private fun initClient(apiKey: String, result: MethodChannel.Result) {
        try {
            AMapLocationClient.updatePrivacyShow(appContext, true, true)
            AMapLocationClient.updatePrivacyAgree(appContext, true)
            if (client == null) {
                val created = AMapLocationClient(appContext)
                created.setLocationListener(listener)
                client = created
            }
            client?.setApiKey(apiKey)
            result.success(true)
        } catch (e: Exception) {
            result.error("AMAP_INIT", e.message ?: "高德定位初始化失败", null)
        }
    }

    private fun fetchOnce(result: MethodChannel.Result) {
        val active = client
        if (active == null) {
            result.error("AMAP_NOT_INIT", "高德定位尚未初始化", null)
            return
        }
        if (pendingOnce != null) {
            result.error("AMAP_BUSY", "已有单次定位在进行中", null)
            return
        }
        pendingOnce = result
        try {
            active.setLocationOption(onceOption())
            active.startLocation()
        } catch (e: Exception) {
            pendingOnce = null
            result.error("AMAP_START", e.message ?: "高德定位启动失败", null)
        }
    }

    private fun startWatch() {
        val active = client
        if (active == null) {
            eventSink?.error("AMAP_NOT_INIT", "高德定位尚未初始化", null)
            return
        }
        watching = true
        try {
            active.setLocationOption(watchOption())
            active.startLocation()
        } catch (e: Exception) {
            watching = false
            eventSink?.error("AMAP_START", e.message ?: "高德定位启动失败", null)
        }
    }

    private fun stopWatch() {
        watching = false
        // 单次定位进行中时不要误停它（共用同一个 client）。
        if (pendingOnce == null) {
            client?.stopLocation()
        }
    }

    /** Activity 销毁时释放原生客户端。 */
    fun dispose() {
        try {
            client?.stopLocation()
            client?.onDestroy()
        } catch (e: Exception) {
            // 销毁阶段异常无处可报，忽略。
        }
        client = null
        pendingOnce = null
        eventSink = null
        watching = false
    }

    private fun onceOption(): AMapLocationClientOption {
        val option = AMapLocationClientOption()
        option.setLocationMode(AMapLocationClientOption.AMapLocationMode.Hight_Accuracy)
        option.setOnceLocation(true)
        // 3 秒内最近一次高精度结果优先返回，减少首定等待。
        option.setOnceLocationLatest(true)
        option.setNeedAddress(false)
        option.setMockEnable(false)
        option.setHttpTimeOut(10_000)
        return option
    }

    private fun watchOption(): AMapLocationClientOption {
        val option = AMapLocationClientOption()
        option.setLocationMode(AMapLocationClientOption.AMapLocationMode.Hight_Accuracy)
        option.setOnceLocation(false)
        option.setInterval(2_000)
        option.setNeedAddress(false)
        option.setMockEnable(false)
        option.setHttpTimeOut(10_000)
        return option
    }

    private fun AMapLocation.toPayload(): Map<String, Any?> = mapOf(
        "latitude" to latitude,
        "longitude" to longitude,
        "accuracy" to accuracy.toDouble(),
        "speed" to speed.toDouble(),
        "timeMillis" to time,
        "errorCode" to errorCode,
        "errorInfo" to (errorInfo ?: ""),
        "locationType" to locationType,
    )

    companion object {
        private const val METHOD_CHANNEL = "com.shitu.app/amap_location"
        private const val EVENT_CHANNEL = "com.shitu.app/amap_location_stream"
    }
}
