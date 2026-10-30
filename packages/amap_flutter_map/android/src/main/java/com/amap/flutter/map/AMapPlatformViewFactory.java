package com.amap.flutter.map;

import android.content.Context;

import com.amap.api.maps.model.CameraPosition;
import com.amap.flutter.map.utils.BreadcrumbUtil;
import com.amap.flutter.map.utils.ConvertUtil;
import com.amap.flutter.map.utils.LogUtil;

import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

/**
 * @author whm
 * @date 2020/10/27 4:08 PM
 * @mail hongming.whm@alibaba-inc.com
 * @since
 */
class AMapPlatformViewFactory extends PlatformViewFactory {
    private static final String CLASS_NAME = "AMapPlatformViewFactory";
    private final BinaryMessenger binaryMessenger;
    private final LifecycleProvider lifecycleProvider;
    AMapPlatformViewFactory(BinaryMessenger binaryMessenger,
                            LifecycleProvider lifecycleProvider) {
        super(StandardMessageCodec.INSTANCE);
        this.binaryMessenger = binaryMessenger;
        this.lifecycleProvider = lifecycleProvider;
    }

    @Override
    public PlatformView create(Context context, int viewId, Object args) {
        final AMapOptionsBuilder builder = new AMapOptionsBuilder();
        Map<String, Object> params = null;
        try {
            ConvertUtil.density = context.getResources().getDisplayMetrics().density;
            // [vendored patch] 建图前初始化 ConvertUtil 的 FlutterLoader（资源标记用）。
            ConvertUtil.initialize(context);
            params = (Map<String, Object>) args;
            LogUtil.i(CLASS_NAME,"create params==>" + params);
            if (params.containsKey("privacyStatement")) {
                ConvertUtil.setPrivacyStatement(context, params.get("privacyStatement"));
                // [vendored patch] 面包屑打点：隐私注入完成（见 BreadcrumbUtil）。
                BreadcrumbUtil.mark(context, "java_privacy_done");
            }

            Object options = ((Map<String, Object>) args).get("options");
            if(null != options) {
                ConvertUtil.interpretAMapOptions(options, builder);
            }

            if (params.containsKey("initialCameraPosition")) {
                CameraPosition cameraPosition = ConvertUtil.toCameraPosition(params.get("initialCameraPosition"));
                builder.setCamera(cameraPosition);
            }

            if (params.containsKey("markersToAdd")) {
                builder.setInitialMarkers(params.get("markersToAdd"));
            }
            if (params.containsKey("polylinesToAdd")) {
                builder.setInitialPolylines(params.get("polylinesToAdd"));
            }

            if (params.containsKey("polygonsToAdd")) {
                builder.setInitialPolygons(params.get("polygonsToAdd"));
            }


            if (params.containsKey("apiKey")) {
                ConvertUtil.checkApiKey(params.get("apiKey"));
                // [vendored patch] 面包屑打点：Key 注入完成（见 BreadcrumbUtil）。
                BreadcrumbUtil.mark(context, "java_apikey_done");
            }

            if (params.containsKey("debugMode")) {
                LogUtil.isDebugMode = ConvertUtil.toBoolean(params.get("debugMode"));
            }

        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "create", e);
            // [vendored patch] 异常可见：被吞掉的异常同步写进面包屑文件，
            // 让 App 内诊断能看到异常类名，而不只是 logcat（见 BreadcrumbUtil）。
            BreadcrumbUtil.error(context, e);
        }
        return builder.build(viewId, context, binaryMessenger, lifecycleProvider);
    }
}
