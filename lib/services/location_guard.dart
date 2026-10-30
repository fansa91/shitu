import 'package:shared_preferences/shared_preferences.dart';

/// bool 型键值存储抽象：守卫逻辑只依赖它，生产走 SharedPreferences，
/// 单测用内存实现。
abstract interface class BoolStore {
  Future<bool> read(String key);
  Future<void> write(String key, bool value);
}

/// SharedPreferences 实现的 [BoolStore]。
class PrefsBoolStore implements BoolStore {
  const PrefsBoolStore();

  @override
  Future<bool> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  @override
  Future<void> write(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}

/// 高德定位的崩溃守卫（复用原生地图时代验证过的「启动标记」模式）：
/// 高德定位仍是原生库，若它在某台设备上像地图渲染器那样进程级硬崩，
/// 不能让 App 每次定位都崩。机制：
/// - 启动一次高德定位前 [tryBegin] 落「进行中」标记；
/// - 收到首个成功定位后 [markSuccess] 清除标记；
/// - App 下次启动 [settleOnLaunch] 若发现标记残留（说明上次在定位
///   过程中进程没了），判定疑似崩溃 → 置「已跳闸」：自动模式跳过
///   高德走系统、设置页注明，用户可在设置页手动重试（[resetByUser]）。
///
/// 每次操作都直读存储（不缓存），设置页与定位服务各自持有实例、
/// 以存储为唯一真相，不会状态不一致。
class AmapLocationGuard {
  AmapLocationGuard({BoolStore? store})
    : _store = store ?? const PrefsBoolStore();

  final BoolStore _store;

  static const _kInflight = 'amap_location_inflight';
  static const _kTripped = 'amap_location_guard_tripped';

  /// App 启动时结算上一次的「进行中」标记：
  /// 残留 = 上次高德定位未等到首个成功结果进程就结束了。
  /// 返回 true 表示本次启动新跳闸（此前未跳闸且发现残留）。
  Future<bool> settleOnLaunch() async {
    final inflight = await _store.read(_kInflight);
    if (!inflight) return false;
    await _store.write(_kInflight, false);
    if (await _store.read(_kTripped)) return false;
    await _store.write(_kTripped, true);
    return true;
  }

  /// 是否已跳闸（跳闸后不应再自动尝试高德定位）。
  Future<bool> isTripped() => _store.read(_kTripped);

  /// 尝试开始一次高德定位：未跳闸则落「进行中」标记并返回 true；
  /// 已跳闸返回 false（调用方应改走系统定位）。
  Future<bool> tryBegin() async {
    if (await _store.read(_kTripped)) return false;
    await _store.write(_kInflight, true);
    return true;
  }

  /// 首个成功定位到达：清除「进行中」标记（本次尝试是安全的）。
  Future<void> markSuccess() => _store.write(_kInflight, false);

  /// 用户在设置页手动重试：清除跳闸与进行中标记，允许再次尝试高德。
  Future<void> resetByUser() async {
    await _store.write(_kTripped, false);
    await _store.write(_kInflight, false);
  }
}
