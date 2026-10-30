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

/// 原生（Java）侧步骤名 → 中文展示名。vendored 高德插件在建图链路的原生
/// 关键点（隐私/Key 注入、MapView 构造、getMap、onCreate）与 Dart 写同一个
/// 面包屑文件（步骤名带 `java_` 前缀），让 Dart 到不了的原生窗口也能见光；
/// 构造期被原生 catch (Throwable) 吞掉的异常写成 `java_error:<异常类名>`。
const Map<String, String> _javaStepLabels = {
  'java_privacy_done': '原生：隐私注入完成',
  'java_apikey_done': '原生：Key 注入完成',
  'java_mapview_ctor_start': '原生：地图视图构造开始',
  'java_mapview_ctor_done': '原生：地图视图构造完成',
  'java_getmap_done': '原生：地图实例取得',
  'java_oncreate_done': '原生：地图 onCreate 完成',
};

/// 任意落盘步骤名的展示文案：Dart 已知步骤用枚举中文名，Java 步骤查上表，
/// `java_error:<类名>` 展示为「原生异常：<类名>」，未登记的 Java 步骤与
/// 其它未知名字原样展示（不丢信息）。
String breadcrumbLabel(String wireName, MapBreadcrumbStep? step) {
  if (step != null) return step.label;
  if (wireName.startsWith('java_error:')) {
    return '原生异常：${wireName.substring('java_error:'.length)}';
  }
  return _javaStepLabels[wireName] ?? wireName;
}

/// 一条面包屑：步骤 + 发生时间。
///
/// Dart 自己落盘的步骤恒有 [step]；Java 侧写进同一文件的步骤不在 Dart
/// 枚举里，[step] 为 null、靠 [wireName] 原样识别。两者编解码格式相同
/// （`名称|毫秒时间戳`)，解析时一视同仁地保留顺序。
class MapBreadcrumb {
  const MapBreadcrumb(this.step, this.at) : wireNameRaw = null;

  const MapBreadcrumb.rawStep(this.wireNameRaw, this.at) : step = null;

  /// Dart 已知步骤；Java 侧步骤为 null。
  final MapBreadcrumbStep? step;

  /// Java 侧步骤的原始落盘名；Dart 步骤为 null（用 [MapBreadcrumbStep.wireName]）。
  final String? wireNameRaw;

  final DateTime at;

  String get wireName => wireNameRaw ?? step!.wireName;

  /// 给用户看的中文名（横幅/诊断区用）。
  String get label => breadcrumbLabel(wireName, step);

  String encode() => '$wireName|${at.millisecondsSinceEpoch}';

  static MapBreadcrumb? decode(String line) {
    final sep = line.lastIndexOf('|');
    if (sep <= 0) return null;
    final name = line.substring(0, sep);
    final millis = int.tryParse(line.substring(sep + 1));
    if (millis == null) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(millis);
    final step = MapBreadcrumbStep.fromWireName(name);
    if (step != null) return MapBreadcrumb(step, at);
    // Java 侧步骤（含 java_error:<异常类名>）：不在 Dart 枚举里，原样保留，
    // 否则原生窗口里的最后一步会被解析丢弃、自保永远只报「地图创建开始」。
    if (name.startsWith('java_')) return MapBreadcrumb.rawStep(name, at);
    return null;
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
/// 停留步 = 该轮最后一条面包屑（可能是 Java 侧步骤/异常，故返回面包屑
/// 本身而非枚举，展示走 [MapBreadcrumb.label]）。
({bool tripped, MapBreadcrumb? stoppedAt}) evaluateCrashGuard(
  List<MapBreadcrumb> previousRound,
) {
  if (previousRound.isEmpty) return (tripped: false, stoppedAt: null);
  final survived = previousRound.any(
    (b) =>
        b.step == MapBreadcrumbStep.firstFrame ||
        b.step == MapBreadcrumbStep.mapDisposedClean,
  );
  if (survived) return (tripped: false, stoppedAt: null);
  return (tripped: true, stoppedAt: previousRound.last);
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
  MapBreadcrumb? _stoppedAt;

  /// 上一轮是否死在建图过程中（本轮应自动回落示意地图）。
  bool get guardTripped => _tripped;

  /// 上一轮停留的那条面包屑（触发自保时非空；展示用其 label/wireName，
  /// 可能是 Dart 步骤，也可能是 Java 侧步骤或 `java_error:<异常类名>`）。
  MapBreadcrumb? get stoppedAt => _stoppedAt;

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

  static String _roundText(List<MapBreadcrumb> round) =>
      round.map((b) => '${b.label} ${_clock(b.at)}').join(' → ');

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
