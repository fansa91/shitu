import 'package:flutter/foundation.dart';

import '../models/located_fix.dart';

/// 定位运行时状态（进程内单例）：LocationService 每次成功定位 /
/// 每次回落后更新，设置页据此显示「当前实际生效的定位源」与守卫
/// 注记。只是展示状态，不参与选路决策。
class LocationRuntimeStatus extends ChangeNotifier {
  LocationRuntimeStatus();

  /// 进程内共享实例（LocationService 默认写它，设置页读它）。
  static final LocationRuntimeStatus instance = LocationRuntimeStatus();

  LocationSource? _activeSource;
  String? _note;
  double? _lastAccuracyMeters;
  LocationSource? _lastFixSource;

  /// 最近一次实际出结果的定位源；本次运行尚无成功定位时为 null。
  LocationSource? get activeSource => _activeSource;

  /// 补充说明（如已自动回落系统、守卫跳闸），无则为 null。
  String? get note => _note;

  /// 最近一次定位的精度半径（米）；后端未提供时为 null。
  /// 设置页据此让用户判断偏移量级（10 米级属精度本身，
  /// 数百米才是坐标系问题）。
  double? get lastAccuracyMeters => _lastAccuracyMeters;

  /// 最近一次定位结果的来源（与 [activeSource] 冗余保存，
  /// 供精度行连来源一起展示）。
  LocationSource? get lastFixSource => _lastFixSource;

  /// 记录最近一次成功定位（LocationService 每次出结果时调用）。
  void reportLastFix(LocatedFix fix) {
    _lastAccuracyMeters = fix.accuracyMeters;
    _lastFixSource = fix.source;
    notifyListeners();
  }

  void reportSuccess(LocationSource source) {
    _activeSource = source;
    _note = null;
    notifyListeners();
  }

  void reportFallback(String note) {
    _activeSource = LocationSource.system;
    _note = note;
    notifyListeners();
  }

  void reportNote(String? note) {
    _note = note;
    notifyListeners();
  }
}
