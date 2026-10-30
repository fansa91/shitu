package com.shitu.shitu

import android.app.Activity
import android.content.Context
import android.os.Bundle
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.MapsInitializer
import com.amap.api.maps.TextureMapView
import com.amap.api.maps.model.LatLng
import com.amap.api.maps.model.MarkerOptions

/**
 * 原生地图探针页（实验）：把 [TextureMapView] 直接挂在本 Activity 的
 * 视图树上（普通安卓原生承载），完全绕开 Flutter 平台视图嵌入层。
 *
 * 背景：高德原生地图经 Flutter 平台视图嵌入时，在用户设备（一加 7 Pro）
 * 上死于 GL 首帧，六个版本二分已收口。本探针只换「承载方式」这一个
 * 变量——同一代 SDK（组合包 10.1.600）、同样的运行时 Key、同样的
 * TextureMapView——验证该机在原生承载下能否出图。探针只做这一件事：
 * 不画路线、不做搜索。
 *
 * Key 与目标点由 Dart 侧经 Intent extras 传入（运行时注入，严禁把
 * Key 写进 Manifest 或硬编码）。进入顺序：隐私三件套 →
 * [MapsInitializer.setApiKey] → 建图 → 地图加载完成回调里移相机并
 * 打标记。
 *
 * 结果留痕：onCreate 先写探针状态 `started`、地图加载成功写 `loaded`
 * （含时间戳），写在 Flutter 的 SharedPreferences 文件里供 Dart 侧
 * 设置页读取（键名约定见 Dart 侧 native_map_probe.dart 的注释）。
 * 若进程在建图时硬崩，状态会停留在 `started`，设置页据此判读
 * 「上次启动后未完成——疑似崩溃」。
 *
 * 注意：本文件在本机无 Android SDK 未经编译，首编译在 CI 出包轮次；
 * 写时已按组合包 jar 用 javap 逐项核对 MapsInitializer /
 * TextureMapView / AMap 的方法签名。
 */
class NativeMapProbeActivity : Activity() {

    private var mapView: TextureMapView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 先落 started：之后任何一步硬崩，痕迹都停在这里。
        writeProbeState(STATE_STARTED)

        val apiKey = intent.getStringExtra(EXTRA_API_KEY) ?: ""
        val lat = if (intent.hasExtra(EXTRA_LATITUDE)) {
            intent.getDoubleExtra(EXTRA_LATITUDE, DEFAULT_LATITUDE)
        } else {
            DEFAULT_LATITUDE
        }
        val lng = if (intent.hasExtra(EXTRA_LONGITUDE)) {
            intent.getDoubleExtra(EXTRA_LONGITUDE, DEFAULT_LONGITUDE)
        } else {
            DEFAULT_LONGITUDE
        }

        // 隐私声明必须在任何高德 SDK 初始化之前（与定位桥同一口径）。
        MapsInitializer.updatePrivacyShow(this, true, true)
        MapsInitializer.updatePrivacyAgree(this, true)
        MapsInitializer.setApiKey(apiKey)

        val view = TextureMapView(this)
        mapView = view
        setContentView(view)
        view.onCreate(savedInstanceState)

        val target = LatLng(lat, lng)
        val map = view.map
        map.setOnMapLoadedListener {
            // 地图加载完成 = 原生 GL 渲染管线已真正跑通，探针目标达成。
            writeProbeState(STATE_LOADED)
            map.moveCamera(CameraUpdateFactory.newLatLngZoom(target, CAMERA_ZOOM))
            map.addMarker(
                MarkerOptions().position(target).title("探针点"),
            )
        }
    }

    override fun onResume() {
        super.onResume()
        mapView?.onResume()
    }

    override fun onPause() {
        mapView?.onPause()
        super.onPause()
    }

    override fun onDestroy() {
        mapView?.onDestroy()
        mapView = null
        super.onDestroy()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        mapView?.onSaveInstanceState(outState)
    }

    /** 状态写进 Flutter 的 SharedPreferences 文件（键带 flutter. 前缀）。 */
    private fun writeProbeState(state: String) {
        try {
            getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(PREF_KEY_STATE, state)
                .putLong(PREF_KEY_UPDATED_AT, System.currentTimeMillis())
                .apply()
        } catch (e: Exception) {
            // 留痕失败不影响探针本体，静默。
        }
    }

    companion object {
        const val EXTRA_API_KEY = "apiKey"
        const val EXTRA_LATITUDE = "latitude"
        const val EXTRA_LONGITUDE = "longitude"

        // 与 Dart 侧 shared_preferences 插件的存储约定对齐：
        // 插件在安卓用名为 FlutterSharedPreferences 的文件、键自动加
        // 「flutter.」前缀。Dart 侧以 native_probe_state /
        // native_probe_updated_at 两个键读取。
        private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
        private const val PREF_KEY_STATE = "flutter.native_probe_state"
        private const val PREF_KEY_UPDATED_AT = "flutter.native_probe_updated_at"

        private const val STATE_STARTED = "started"
        private const val STATE_LOADED = "loaded"

        // 无当前定位时的默认点：天安门（GCJ-02）。
        private const val DEFAULT_LATITUDE = 39.908722
        private const val DEFAULT_LONGITUDE = 116.397499
        private const val CAMERA_ZOOM = 16f
    }
}
