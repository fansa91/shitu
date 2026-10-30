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
 * 探针二号（v0.3.2）：只换渲染器一个变量——SDK 由一号的地图组合包
 * 10.1.600（libAMapSDK_MAP）换成**导航 SDK 合包 9.8.3**
 * （libAMapSDK_NAVI_v9_8_3.so，flavor map3dnavisearchloc）。背景：
 * 地图线三个版本在 Flutter 嵌入与原生直挂两种承载下都死于 GL 首帧
 * （无弹窗秒退＝原生层硬崩），而 bmap 用导航线这份二进制在同一台
 * 一加 7 Pro 上能正常开图。承载、视图类（导航包内同名
 * TextureMapView）、运行时 Key 注入方式全部与一号保持不变。
 * SDK 的来源与选型见 app 的 build.gradle.kts 依赖注释（Maven 无
 * 9.8.3 导航合包，本地 jar 与 bmap 的二进制同源）。
 *
 * Key 与目标点由 Dart 侧经 Intent extras 传入（运行时注入，严禁把
 * Key 写进 Manifest 或硬编码）。进入顺序：隐私三件套 →
 * [MapsInitializer.setApiKey] → 建图 → 地图加载完成回调里移相机并
 * 打标记。探针只做这一件事：不画路线、不做搜索。
 *
 * 结果留痕（分步）：每个阶段完成、下一阶段开始**前**，先把该阶段
 * 的完成标记写进 Flutter 的 SharedPreferences 文件（键名约定见
 * Dart 侧 native_map_probe.dart），地图加载成功写终态 `loaded`。
 * 若进程在某个阶段里硬崩，痕迹停在上一个完成标记，设置页据此
 * 判读死点区间：started → privacy_done → key_set → view_created →
 * oncreate_done → onresume_done → loaded，可区分死在构造期、
 * 生命周期还是首帧之后（一号只有 started/loaded 两态，死点不精，
 * 这是二号的改进点）。
 *
 * 注意：本文件在本机无 Android SDK 未经编译，首编译在 CI 出包轮次；
 * 写时已按导航合包 jar 用 javap 逐项核对 MapsInitializer /
 * TextureMapView / AMap 的方法签名。
 */
class NativeMapProbeActivity : Activity() {

    private var mapView: TextureMapView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 先落 started：之后任何一步硬崩，痕迹至少停在这里。
        writeProbeState(STEP_STARTED)

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
        writeProbeState(STEP_PRIVACY_DONE)

        MapsInitializer.setApiKey(apiKey)
        writeProbeState(STEP_KEY_SET)

        val view = TextureMapView(this)
        mapView = view
        setContentView(view)
        writeProbeState(STEP_VIEW_CREATED)

        view.onCreate(savedInstanceState)
        writeProbeState(STEP_ONCREATE_DONE)

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
        // onResume 返回后落痕：下一次硬崩若停在这里，说明已过
        // 生命周期、死点在首帧渲染或其后。
        writeProbeState(STEP_ONRESUME_DONE)
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

        // 分步留痕的步骤名（与 Dart 侧判读约定一致，勿改名）：
        // 每阶段完成后落盘，loaded 为唯一成功终态。
        private const val STEP_STARTED = "started"
        private const val STEP_PRIVACY_DONE = "privacy_done"
        private const val STEP_KEY_SET = "key_set"
        private const val STEP_VIEW_CREATED = "view_created"
        private const val STEP_ONCREATE_DONE = "oncreate_done"
        private const val STEP_ONRESUME_DONE = "onresume_done"
        private const val STATE_LOADED = "loaded"

        // 无当前定位时的默认点：天安门（GCJ-02）。
        private const val DEFAULT_LATITUDE = 39.908722
        private const val DEFAULT_LONGITUDE = 116.397499
        private const val CAMERA_ZOOM = 16f
    }
}
