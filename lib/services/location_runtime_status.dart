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

  /// 最近一次实际出结果的定位源；本次运行尚无成功定位时为 null。
  LocationSource? get activeSource => _activeSource;

  /// 补充说明（如已自动回落系统、守卫跳闸），无则为 null。
  String? get note => _note;

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
