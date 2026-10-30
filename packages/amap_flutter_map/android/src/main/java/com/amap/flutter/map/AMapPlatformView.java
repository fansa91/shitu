package com.amap.flutter.map;

import android.content.Context;
import android.os.Bundle;
import android.view.View;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.lifecycle.DefaultLifecycleObserver;
import androidx.lifecycle.LifecycleOwner;

import com.amap.api.maps.AMap;
import com.amap.api.maps.AMapOptions;
import com.amap.api.maps.TextureMapView;
// [vendored patch] 视图类选择（补丁 1 → 补丁 12 反转）：补丁 1 曾把官方原版
// TextureMapView 换成 MapView（SurfaceView）二分渲染路径；v0.2.5 真机实测
// MapView 创建链（构造/getMap/onCreate）全程走通、进程死在 onCreate 之后的
// 渲染启动段，故补丁 12 换回 TextureMapView（TextureView 路径）继续二分。
// 两者构造器/生命周期/getMap 的 API 面已对 8.1.0 官方 jar 用 javap 核验一致。
import com.amap.flutter.map.core.MapController;
import com.amap.flutter.map.overlays.marker.MarkersController;
import com.amap.flutter.map.overlays.polygon.PolygonsController;
import com.amap.flutter.map.overlays.polyline.PolylinesController;
import com.amap.flutter.map.utils.BreadcrumbUtil;
import com.amap.flutter.map.utils.LogUtil;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.platform.PlatformView;


/**
 * @author whm
 * @date 2020/10/27 5:49 PM
 * @mail hongming.whm@alibaba-inc.com
 * @since
 */
public class AMapPlatformView
        implements
        DefaultLifecycleObserver,
        ActivityPluginBinding.OnSaveInstanceStateListener,
        MethodChannel.MethodCallHandler,
        PlatformView {
    private static final String CLASS_NAME = "AMapPlatformView";
    private final MethodChannel methodChannel;

    private MapController mapController;
    private MarkersController markersController;
    private PolylinesController polylinesController;
    private PolygonsController polygonsController;

    // [vendored patch] 字段名沿用 mapView，类型为补丁 12 换回的 TextureMapView。
    private TextureMapView mapView;

    // [vendored patch] 留存 Context 供生命周期回调里的面包屑打点/异常可见使用。
    private final Context context;

    private boolean disposed = false;

    private final Map<String, MyMethodCallHandler> myMethodCallHandlerMap;

    AMapPlatformView(int id,
                     Context context,
                     BinaryMessenger binaryMessenger,
                     LifecycleProvider lifecycleProvider,
                     AMapOptions options) {

        this.context = context;
        methodChannel = new MethodChannel(binaryMessenger, "amap_flutter_map_" + id);
        methodChannel.setMethodCallHandler(this);
        myMethodCallHandlerMap = new HashMap<String, MyMethodCallHandler>(8);

        try {
            // [vendored patch] 面包屑打点：地图视图构造窗口（见 BreadcrumbUtil）。
            // 步骤 wire 名沿用 java_mapview_*（历史记录与 Dart 展示映射已按此名
            // 落盘，不因补丁 12 换视图类而改名）。
            BreadcrumbUtil.mark(context, "java_mapview_ctor_start");
            mapView = new TextureMapView(context, options);
            BreadcrumbUtil.mark(context, "java_mapview_ctor_done");
            AMap amap = mapView.getMap();
            BreadcrumbUtil.mark(context, "java_getmap_done");
            // [vendored patch] 渲染段打点（补丁 12）：附加一个只打点的
            // OnMapLoadedListener。MapController 自身以 addOnMapLoadedListener
            // 注册，附加不冲突、不改变既有就绪流程；触发即证明首帧渲染与
            // 瓦片加载链已跑通（死在渲染启动段时此步不会出现）。
            amap.addOnMapLoadedListener(new AMap.OnMapLoadedListener() {
                @Override
                public void onMapLoaded() {
                    BreadcrumbUtil.mark(context, "java_map_loaded");
                }
            });
            mapController = new MapController(methodChannel, mapView);
            markersController = new MarkersController(methodChannel, amap);
            polylinesController = new PolylinesController(methodChannel, amap);
            polygonsController = new PolygonsController(methodChannel, amap);
            initMyMethodCallHandlerMap();
            lifecycleProvider.getLifecycle().addObserver(this);
            // [vendored patch] 渲染段打点（补丁 12）：平台视图构造器末尾，
            // 与 java_mapview_ctor_done（仅 new 视图完成）区分——两者之间还隔
            // 着 getMap 与四个 controller 的初始化。
            BreadcrumbUtil.mark(context, "java_ctor_done");
        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "<init>", e);
            // [vendored patch] 异常可见：构造期被吞掉的 Java 异常（如 .so 加载
            // 失败）同步写进面包屑（见 BreadcrumbUtil）。
            BreadcrumbUtil.error(context, e);
        }
    }

    private void initMyMethodCallHandlerMap() {
        String[] methodIdArray = mapController.getRegisterMethodIdArray();
        if (null != methodIdArray && methodIdArray.length > 0) {
            for (String methodId : methodIdArray) {
                myMethodCallHandlerMap.put(methodId, mapController);
            }
        }

        methodIdArray = markersController.getRegisterMethodIdArray();
        if (null != methodIdArray && methodIdArray.length > 0) {
            for (String methodId : methodIdArray) {
                myMethodCallHandlerMap.put(methodId, markersController);
            }
        }

        methodIdArray = polylinesController.getRegisterMethodIdArray();
        if (null != methodIdArray && methodIdArray.length > 0) {
            for (String methodId : methodIdArray) {
                myMethodCallHandlerMap.put(methodId, polylinesController);
            }
        }

        methodIdArray = polygonsController.getRegisterMethodIdArray();
        if (null != methodIdArray && methodIdArray.length > 0) {
            for (String methodId : methodIdArray) {
                myMethodCallHandlerMap.put(methodId, polygonsController);
            }
        }
    }


    public MapController getMapController() {
        return mapController;
    }

    public MarkersController getMarkersController() {
        return markersController;
    }

    public PolylinesController getPolylinesController() {
        return polylinesController;
    }

    public PolygonsController getPolygonsController() {
        return polygonsController;
    }


    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        LogUtil.i(CLASS_NAME, "onMethodCall==>" + call.method + ", arguments==> " + call.arguments);
        String methodId = call.method;
        if (myMethodCallHandlerMap.containsKey(methodId)) {
            myMethodCallHandlerMap.get(methodId).doMethodCall(call, result);
        } else {
            LogUtil.w(CLASS_NAME, "onMethodCall, the methodId: " + call.method + ", not implemented");
            result.notImplemented();
        }
    }


    @Override
    public void onCreate(@NonNull LifecycleOwner owner) {
        LogUtil.i(CLASS_NAME, "onCreate==>");
        try {
            if (disposed) {
                return;
            }
            if (null != mapView) {
                mapView.onCreate(null);
                // [vendored patch] 面包屑打点：地图视图 onCreate 完成。
                BreadcrumbUtil.mark(context, "java_oncreate_done");
            }
        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "onCreate", e);
            // [vendored patch] 异常可见（见 BreadcrumbUtil）。
            BreadcrumbUtil.error(context, e);
        }
    }

    @Override
    public void onStart(@NonNull LifecycleOwner owner) {
        LogUtil.i(CLASS_NAME, "onStart==>");
    }

    @Override
    public void onResume(@NonNull LifecycleOwner owner) {
        LogUtil.i(CLASS_NAME, "onResume==>");
        try {
            if (disposed) {
                return;
            }
            if (null != mapView) {
                // [vendored patch] 渲染段打点（补丁 12）：onResume 前后夹住
                // 地图视图的渲染启动调用——v0.2.5 的死亡窗口正在 onCreate
                // 之后、渲染起来之前，这对步骤用来确认死点是否已越过此处。
                BreadcrumbUtil.mark(context, "java_onresume_start");
                mapView.onResume();
                BreadcrumbUtil.mark(context, "java_onresume_done");
            }
        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "onResume", e);
            // [vendored patch] 异常可见（见 BreadcrumbUtil；与 onCreate 一致，
            // 此前 onResume 的 catch 只记 LogUtil，补齐）。
            BreadcrumbUtil.error(context, e);
        }
    }

    @Override
    public void onPause(@NonNull LifecycleOwner owner) {
        LogUtil.i(CLASS_NAME, "onPause==>");
        try {
            if (disposed) {
                return;
            }
            mapView.onPause();
        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "onPause", e);
        }
    }

    @Override
    public void onStop(@NonNull LifecycleOwner owner) {
        LogUtil.i(CLASS_NAME, "onStop==>");
    }

    @Override
    public void onDestroy(@NonNull LifecycleOwner owner) {
        LogUtil.i(CLASS_NAME, "onDestroy==>");
        try {
            if (disposed) {
                return;
            }
            destroyMapViewIfNecessary();
        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "onDestroy", e);
        }
    }

    @Override
    public void onSaveInstanceState(@NonNull Bundle bundle) {
        LogUtil.i(CLASS_NAME, "onDestroy==>");
        try {
            if (disposed) {
                return;
            }
            mapView.onSaveInstanceState(bundle);
        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "onSaveInstanceState", e);
        }
    }

    @Override
    public void onRestoreInstanceState(@Nullable Bundle bundle) {
        LogUtil.i(CLASS_NAME, "onDestroy==>");
        try {
            if (disposed) {
                return;
            }
            mapView.onCreate(bundle);
        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "onRestoreInstanceState", e);
        }
    }


    @Override
    public View getView() {
        LogUtil.i(CLASS_NAME, "getView==>");
        return mapView;
    }

    @Override
    public void dispose() {
        LogUtil.i(CLASS_NAME, "dispose==>");
        try {
            if (disposed) {
                return;
            }
            methodChannel.setMethodCallHandler(null);
            destroyMapViewIfNecessary();
            disposed = true;
        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "dispose", e);
        }
    }

    private void destroyMapViewIfNecessary() {
        if (mapView == null) {
            return;
        }
        mapView.onDestroy();
    }


}
