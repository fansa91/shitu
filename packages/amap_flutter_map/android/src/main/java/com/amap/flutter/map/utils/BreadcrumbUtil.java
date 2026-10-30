package com.amap.flutter.map.utils;

import android.content.Context;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

/**
 * [vendored patch] 建图面包屑（原生侧）。
 *
 * 与 Dart 侧 MapCrashGuard 写同一个文件：应用支持目录下的
 * amap_map_breadcrumbs.txt（path_provider 在 Android 上的
 * getApplicationSupportDirectory 对应 Context.getFilesDir()），格式同为
 * 「步骤名|毫秒时间戳」一行一条、追加写、写后立即关闭，确保进程被原生
 * 崩溃杀死时已落盘。
 *
 * Dart 枚举覆盖不到的原生窗口（隐私/Key 注入、MapView 构造、getMap、
 * onCreate）靠 java_ 前缀步骤照亮；构造链路上被 catch (Throwable) 吞掉的
 * Java 异常（如 .so 加载失败 UnsatisfiedLinkError）另写一行
 * 「java_error:&lt;异常类名&gt;」，让「不崩也不出图」能在 App 内诊断里
 * 直接可见，而不是只躺在 logcat 里。
 *
 * 本类任何失败都不得反过来影响建图：全程吞掉自身异常。
 */
public final class BreadcrumbUtil {
    private static final String FILE_NAME = "amap_map_breadcrumbs.txt";

    private BreadcrumbUtil() {
    }

    public static void mark(Context context, String step) {
        if (context == null || step == null) {
            return;
        }
        FileOutputStream out = null;
        try {
            File file = new File(context.getFilesDir(), FILE_NAME);
            String line = step + "|" + System.currentTimeMillis() + "\n";
            out = new FileOutputStream(file, true);
            out.write(line.getBytes(StandardCharsets.UTF_8));
            out.flush();
        } catch (Throwable ignored) {
            // 面包屑只是诊断手段，写失败绝不能影响建图本身。
        } finally {
            if (out != null) {
                try {
                    out.close();
                } catch (Throwable ignored) {
                }
            }
        }
    }

    public static void error(Context context, Throwable e) {
        if (e == null) {
            return;
        }
        // 只写异常类名：message 可能含 '|' 或换行，会破坏面包屑的行格式。
        mark(context, "java_error:" + e.getClass().getSimpleName());
    }
}
