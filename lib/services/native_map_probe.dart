import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/geo_point.dart';
import '../utils/format.dart';

/// 原生地图探针的最近一次结果（原生侧留痕，Dart 侧只读判读）。
enum ProbeOutcome {
  /// 从未打开过探针页。
  neverTried,

  /// 上次地图加载成功（原生 GL 渲染管线跑通）。
  loaded,

  /// 上次停在某个中间步骤就再无下文：过程在该步之后中断——疑似崩溃，
  /// [ProbeStatus.step] 是停住的步骤名。
  stoppedAtStep,
}

/// 探针结果快照：[outcome] + 停住的步骤名 + 留痕时间。
class ProbeStatus {
  const ProbeStatus(this.outcome, this.at, {this.step});

  final ProbeOutcome outcome;

  /// 停住的步骤名（仅 [ProbeOutcome.stoppedAtStep] 时有值）：原生侧
  /// 逐步落盘的步骤标识，如 started / privacy_done / key_set /
  /// view_created / oncreate_done / onresume_done。
  final String? step;

  final DateTime? at;
}

/// 把原生侧写入的原始值解析成 [ProbeStatus]（纯函数，供单测）。
/// 原生侧约定：state 是最后落盘的步骤名（终态为 'loaded'），
/// updatedAt 是毫秒时间戳；state 缺失/为空按从未试过处理，
/// 其余任何值都原样当作「停在这一步」（留痕是尽力而为，不因此报错）。
ProbeStatus parseProbeStatus(String? state, int? updatedAtMillis) {
  if (state == null || state.isEmpty) {
    return const ProbeStatus(ProbeOutcome.neverTried, null);
  }
  final at = updatedAtMillis == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(updatedAtMillis);
  if (state == 'loaded') return ProbeStatus(ProbeOutcome.loaded, at);
  return ProbeStatus(ProbeOutcome.stoppedAtStep, at, step: state);
}

/// 解析留痕文件全文成 [ProbeStatus]（纯函数，供单测）。
/// 文件格式（与原生 NativeMapProbeActivity 的约定）：两行纯文本，
/// 第一行步骤名、第二行毫秒时间戳，如 `onresume_done\n1793412...`。
/// 文件缺失由调用方处理；内容为空/只有空白按从未试过；时间戳缺失
/// 或不可解析时时间为 null、步骤名照常判读（容忍留痕写一半损坏）。
ProbeStatus parseProbeTrace(String? content) {
  if (content == null) {
    return const ProbeStatus(ProbeOutcome.neverTried, null);
  }
  final lines = content
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    return const ProbeStatus(ProbeOutcome.neverTried, null);
  }
  final millis = lines.length > 1 ? int.tryParse(lines[1]) : null;
  return parseProbeStatus(lines.first, millis);
}

/// 设置页探针入口的副标题文案（纯函数，供单测）。
/// 二号探针（导航 SDK 9.8.3）起留痕细化到步骤：非终态直接报停在哪步，
/// 据此区分死在构造期、生命周期还是首帧之后。
String probeStatusText(ProbeStatus status) {
  final at = status.at;
  final suffix = at == null
      ? ''
      : '（${at.month}月${at.day}日 ${formatClock(at)}）';
  return switch (status.outcome) {
    ProbeOutcome.neverTried =>
      '尚未试过：点开验证原生高德地图（导航 SDK 9.8.3 · 独立进程）能否出图',
    ProbeOutcome.loaded => '上次加载成功$suffix',
    ProbeOutcome.stoppedAtStep => '上次停在：${status.step}——疑似崩溃$suffix',
  };
}

/// 打开探针前的前置条件缺失项（纯判读，供单测与设置页共用）。
enum ProbeBlocker {
  /// 尚未填写高德 Android SDK Key（探针页靠它运行时注入建图）。
  missingKey,

  /// 尚未同意高德隐私政策。
  privacyNotAgreed,
}

/// 前置条件检查：都满足返回 null，否则返回第一个缺失项。
ProbeBlocker? probeBlocker({
  required bool hasSdkKey,
  required bool privacyAgreed,
}) {
  if (!hasSdkKey) return ProbeBlocker.missingKey;
  if (!privacyAgreed) return ProbeBlocker.privacyNotAgreed;
  return null;
}

/// 原生地图探针的 Dart 侧门面：读留痕 + 经通道打开探针页。
///
/// 留痕的存储约定（与原生 NativeMapProbeActivity 对齐）：
/// 三号探针起探针页跑在独立进程 `:mapprobe`（只换进程环境一个
/// 变量，验证宿主进程污染假设），SharedPreferences 跨进程不可靠，
/// 留痕改存应用 files 目录下的普通文件 `native_probe_trace`
/// （两行纯文本：步骤名 + 毫秒时间戳）。Dart 侧用
/// [getApplicationSupportDirectory] 定位同一目录——path_provider
/// 安卓实现里 ApplicationSupport 目录正是 Context.filesDir，
/// 与原生侧 filesDir 严格一致（注意：ApplicationDocuments 目录
/// 在安卓上是 filesDir 下的 flutter 子目录，不可混用）。
/// 建图若进程级硬崩，Dart 代码没机会执行，只有原生侧逐步同步
/// 落盘的步骤名能活下来——每一步执行前先写痕，加载成功写终态
/// `loaded`，据此判读死点位置。崩溃只带走探针副进程，主进程
/// 存活，回设置页刷新即可读到停步。
/// 二号及更早写在 SharedPreferences 里的旧留痕键已弃用，不再
/// 读取；没有留痕文件就按未试过处理（旧记录无保留价值）。
class NativeMapProbeService {
  NativeMapProbeService({
    this._channel = const MethodChannel('com.shitu.app/native_map_probe'),
    Future<Directory> Function()? supportDirectory,
  }) : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final MethodChannel _channel;
  final Future<Directory> Function() _supportDirectory;

  /// 留痕文件名（与原生侧约定一致，勿改名）。
  static const traceFileName = 'native_probe_trace';

  /// 读最近一次探针结果：留痕文件不存在/读失败一律按未试过处理
  /// （留痕是尽力而为，判读失败绝不能让设置页报错）。
  Future<ProbeStatus> lastStatus() async {
    try {
      final dir = await _supportDirectory();
      final file = File('${dir.path}/$traceFileName');
      if (!await file.exists()) {
        return const ProbeStatus(ProbeOutcome.neverTried, null);
      }
      return parseProbeTrace(await file.readAsString());
    } catch (_) {
      return const ProbeStatus(ProbeOutcome.neverTried, null);
    }
  }

  /// 打开探针页：Key 运行时经通道传给原生（不落任何清单/代码），
  /// [target] 是当前定位（GCJ-02）；为 null 时原生侧用天安门默认点。
  Future<void> open({required String apiKey, GeoPoint? target}) async {
    await _channel.invokeMethod<bool>('openProbe', {
      'apiKey': apiKey,
      if (target != null) 'latitude': target.latitude,
      if (target != null) 'longitude': target.longitude,
    });
  }
}
