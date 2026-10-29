import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 真实地图创建链路上的关键步骤（面包屑）。
///
/// 一加 7 Pro / Android 10 上填 Key 后打开真实地图进程级闪退（原生崩溃，
/// Dart 层拿不到堆栈、本机无 logcat）。为把崩溃定位到步，在建图链路的
/// 每个关键节点同步落盘一个步骤标记（见 [MapCrashGuard.markStep]）：
/// 下次启动读上一轮的步骤序列，停在哪一步没走完，就知道死在哪里。
enum MapBreadcrumbStep {
  sdkInitStart('sdk_init_start', 'SDK 初始化开始'),
  sdkInitDone('sdk_init_done', 'SDK 初始化完成'),
  mapCreateStart('map_create_start', '地图创建开始'),
  onMapCreated('on_map_created', '地图创建回调'),
  firstFrame('first_frame', '首帧渲染'),
  mapDisposedClean('map_disposed_clean', '地图正常销毁');

  const MapBreadcrumbStep(this.wireName, this.label);

  /// 落盘用的稳定名字（改名会让旧一轮记录读不回来，不要改）。
  final String wireName;

  /// 给用户看的中文名（横幅/诊断区用）。
  final String label;

  static MapBreadcrumbStep? fromWireName(String name) {
    for (final s in values) {
      if (s.wireName == name) return s;
    }
    return null;
  }
}

/// 一条面包屑：步骤 + 发生时间。
class MapBreadcrumb {
  const MapBreadcrumb(this.step, this.at);

  final MapBreadcrumbStep step;
  final DateTime at;

  String encode() => '${step.wireName}|${at.millisecondsSinceEpoch}';

  static MapBreadcrumb? decode(String line) {
    final sep = line.lastIndexOf('|');
    if (sep <= 0) return null;
    final step = MapBreadcrumbStep.fromWireName(line.substring(0, sep));
    final millis = int.tryParse(line.substring(sep + 1));
    if (step == null || millis == null) return null;
    return MapBreadcrumb(step, DateTime.fromMillisecondsSinceEpoch(millis));
  }
}

/// 解析一整轮落盘内容（每行一条面包屑）；坏行跳过，不整体失败。
List<MapBreadcrumb> decodeBreadcrumbRound(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final result = <MapBreadcrumb>[];
  for (final line in raw.split('\n')) {
    final b = MapBreadcrumb.decode(line.trim());
    if (b != null) result.add(b);
  }
  return result;
}

/// 自保判定（纯函数，可单测）：
/// 上一轮只要走过建图链路（非空）、却既没到「首帧渲染」也没到「正常销毁」，
/// 就认定上一轮是死在建图过程中的原生崩溃，本轮触发自保（回落示意地图）。
/// 停留步骤 = 该轮最后一个步骤。
({bool tripped, MapBreadcrumbStep? stoppedAt}) evaluateCrashGuard(
  List<MapBreadcrumb> previousRound,
) {
  if (previousRound.isEmpty) return (tripped: false, stoppedAt: null);
  final steps = previousRound.map((b) => b.step).toSet();
  final survived = steps.contains(MapBreadcrumbStep.firstFrame) ||
      steps.contains(MapBreadcrumbStep.mapDisposedClean);
  if (survived) return (tripped: false, stoppedAt: null);
  return (tripped: true, stoppedAt: previousRound.last.step);
}

/// 面包屑落盘介质（同步 API：原生崩溃随时可能发生，异步写来不及）。
abstract interface class BreadcrumbSink {
  String? read();
  void write(String content);
  void clear();
}

/// 内存介质（测试 / path_provider 不可用时兜底：仅本次运行内有效）。
class MemoryBreadcrumbSink implements BreadcrumbSink {
  String? _content;

  @override
  String? read() => _content;

  @override
  void write(String content) => _content = content;

  @override
  void clear() => _content = null;
}

/// 小文件介质：每次标记都整轮覆写并 flush，进程被原生崩溃杀死也保得住。
class FileBreadcrumbSink implements BreadcrumbSink {
  FileBreadcrumbSink(this._file);

  final File _file;

  @override
  String? read() {
    try {
      return _file.existsSync() ? _file.readAsStringSync() : null;
    } catch (_) {
      return null; // 读不到就当没有上一轮，绝不因此挡住启动
    }
  }

  @override
  void write(String content) {
    try {
      _file.writeAsStringSync(content, flush: true);
    } catch (_) {
      // 落盘失败只损失诊断能力，不能反过来让 App 崩。
    }
  }

  @override
  void clear() {
    try {
      if (_file.existsSync()) _file.deleteSync();
    } catch (_) {}
  }
}

/// 地图崩溃自保状态机：
/// - 构造时读上一轮面包屑并判定是否触发自保（[guardTripped]）；
/// - 本轮建图链路经 [markStep] 逐点落盘（[MapBreadcrumbStep.sdkInitStart]
///   视为新一轮开始，先清空上一轮记录）；
/// - 用户在设置里点「重试真实地图」→ [clearGuardForRetry] 清掉自保与记录。
class MapCrashGuard extends ChangeNotifier {
  MapCrashGuard({required BreadcrumbSink sink}) : _sink = sink {
    _previousRound = decodeBreadcrumbRound(sink.read());
    final verdict = evaluateCrashGuard(_previousRound);
    _tripped = verdict.tripped;
    _stoppedAt = verdict.stoppedAt;
  }

  /// 无落盘能力的空实现（测试、桌面预览等场景：永不触发自保）。
  factory MapCrashGuard.inert() =>
      MapCrashGuard(sink: MemoryBreadcrumbSink());

  /// 正式入口：面包屑文件放应用支持目录（卸载才清，升级保留）。
  static Future<MapCrashGuard> loadDefault() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return MapCrashGuard(
        sink: FileBreadcrumbSink(File('${dir.path}/amap_map_breadcrumbs.txt')),
      );
    } catch (_) {
      return MapCrashGuard.inert();
    }
  }

  final BreadcrumbSink _sink;

  late final List<MapBreadcrumb> _previousRound;
  final List<MapBreadcrumb> _currentRound = [];
  bool _tripped = false;
  MapBreadcrumbStep? _stoppedAt;

  /// 上一轮是否死在建图过程中（本轮应自动回落示意地图）。
  bool get guardTripped => _tripped;

  /// 上一轮停留的步骤（触发自保时非空）。
  MapBreadcrumbStep? get stoppedAt => _stoppedAt;

  List<MapBreadcrumb> get previousRound =>
      List.unmodifiable(_previousRound);

  List<MapBreadcrumb> get currentRound => List.unmodifiable(_currentRound);

  /// 记录一个建图步骤并立即落盘。[sdkInitStart] 视为新一轮开始。
  void markStep(MapBreadcrumbStep step) {
    if (step == MapBreadcrumbStep.sdkInitStart) _currentRound.clear();
    _currentRound.add(MapBreadcrumb(step, DateTime.now()));
    _sink.write(_currentRound.map((b) => b.encode()).join('\n'));
  }

  /// 清除自保状态与全部面包屑（设置里「重试真实地图」调用）。
  void clearGuardForRetry() {
    _tripped = false;
    _stoppedAt = null;
    _previousRound.clear();
    _currentRound.clear();
    _sink.clear();
    notifyListeners();
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  static String _roundText(List<MapBreadcrumb> round) => round
      .map((b) => '${b.step.label} ${_clock(b.at)}')
      .join(' → ');

  /// 诊断区文案（设置 → 关于，可复制）：自保状态 + 两轮步骤序列。
  String breadcrumbReport() {
    final lines = <String>[];
    if (_tripped) {
      lines.add('真实地图自保：已触发（上次停在「${_stoppedAt?.label ?? '未知步骤'}」）');
    } else {
      lines.add('真实地图自保：未触发');
    }
    if (_previousRound.isNotEmpty) {
      lines.add('上一轮步骤：${_roundText(_previousRound)}');
    }
    if (_currentRound.isNotEmpty) {
      lines.add('本轮步骤：${_roundText(_currentRound)}');
    }
    if (_previousRound.isEmpty && _currentRound.isEmpty) {
      lines.add('建图步骤：暂无记录');
    }
    return lines.join('\n');
  }
}
