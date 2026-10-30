package com.shitu.shitu

import android.app.Activity
import android.os.Bundle
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.MapsInitializer
import com.amap.api.maps.TextureMapView
import com.amap.api.maps.model.LatLng
import com.amap.api.maps.model.MarkerOptions
import java.io.File
import java.io.FileOutputStream

/**
 * 原生地图探针页（实验）：把 [TextureMapView] 直接挂在本 Activity 的
 * 视图树上（普通安卓原生承载），完全绕开 Flutter 平台视图嵌入层。
 *
 * 探针二号（v0.3.2）：只换渲染器一个变量——SDK 由一号的地图组合包
 * 10.1.600（libAMapSDK_MAP）换成**导航 SDK 合包 9.8.3**
 * （libAMapSDK_NAVI_v9_8_3.so，flavor map3dnavisearchloc）。结果：
 * 真机留痕仍停在 onResume 后首帧硬崩，与地图线死在同一位置。
 *
 * 探针三号（v0.3.3）：只换**进程环境**这一个变量——本 Activity 在
 * Manifest 里声明 `android:process=":mapprobe"`，跑在独立进程。
 * 依据：历次崩溃（Flutter 嵌入 × 地图线三版本、原生直挂 × 地图/
 * 导航两渲染器）全发生在被 Flutter 引擎与高德定位组件初始化过的
 * 宿主进程内，而 bmap 用同款二进制在同机能跑，它是纯净原生进程。
 * 渲染器、视图类、运行时 Key 注入方式与二号全部不变；独立进程的
 * 附带好处是探针硬崩不再带走主应用，用户回设置页即可读留痕。
 * 进程安全核查：本应用无自定义 Application 类（Manifest 的
 * applicationName 解析为 android.app.Application，onCreate 空
 * 实现），插件注册与定位桥都只绑 MainActivity 的 FlutterEngine，
 * 副进程不建引擎、不跑任何插件初始化，无需进程名守卫。
 *
 * Key 与目标点由 Dart 侧经 Intent extras 传入（运行时注入，严禁把
 * Key 写进 Manifest 或硬编码）。进入顺序：隐私三件套 →
 * [MapsInitializer.setApiKey] → 建图 → 地图加载完成回调里移相机并
 * 打标记。探针只做这一件事：不画路线、不做搜索。
 *
 * 结果留痕（分步，普通文件）：SharedPreferences 跨进程不可靠（副
 * 进程写、主进程读可能读到旧值），三号起改写应用 files 目录下的
 * 普通文件 `native_probe_trace`（路径约定见 Dart 侧
 * native_map_probe.dart：Dart 的 ApplicationSupport 目录在安卓上
 * 即 filesDir）。文件内容两行纯文本：第一行步骤名、第二行毫秒
 * 时间戳；每步写完 flush + sync 再进下一步，若进程在某个阶段里
 * 硬崩，痕迹停在上一个完成标记，设置页据此判读死点区间：
 * started → privacy_done → key_set → view_created → oncreate_done
 * → onresume_done → loaded，可区分死在构造期、生命周期还是首帧
 * 之后。二号及更早写在 SharedPreferences 里的旧留痕键自三号起
 * 弃用，Dart 侧不再读取（读不到留痕文件即按未试过处理）。
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

    /**
     * 状态写进 files 目录下的留痕文件（两行纯文本：步骤名 + 毫秒
     * 时间戳），覆盖全量重写并同步落盘，保证硬崩前痕迹不丢。
     * 本 Activity 跑在 :mapprobe 副进程、Dart 侧在主进程读同一文件，
     * 文件是两边唯一可靠的跨进程介质。
     */
    private fun writeProbeState(state: String) {
        try {
            val file = File(filesDir, TRACE_FILE_NAME)
            FileOutputStream(file, false).use { out ->
                out.write("$state\n${System.currentTimeMillis()}\n".toByteArray(Charsets.UTF_8))
                out.flush()
                out.fd.sync()
            }
        } catch (e: Exception) {
            // 留痕失败不影响探针本体，静默。
        }
    }

    companion object {
        const val EXTRA_API_KEY = "apiKey"
        const val EXTRA_LATITUDE = "latitude"
        const val EXTRA_LONGITUDE = "longitude"

        // 留痕文件名（与 Dart 侧 native_map_probe.dart 的约定一致，
        // 勿改名）：位于应用 files 目录（Dart 侧 ApplicationSupport
        // 目录在安卓上即此目录）。
        private const val TRACE_FILE_NAME = "native_probe_trace"

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
