/// 高德插件初始化门控（纯逻辑，可单测）：
/// - 同一 Key 标识（[keyId]）只真正执行一次初始化（单飞：并发调用共享同一 Future）；
/// - 初始化失败后清掉在途 Future，下一次调用可重试，不会把失败钉死；
/// - Key 标识变化视为需要重新初始化（旧地图应先销毁，由调用方用
///   ValueKey 换新 AmapMapView 保证顺序），重新执行 runner。
class AmapInitGate {
  AmapInitStatus _status = AmapInitStatus.idle;
  String? _activeKeyId;
  String? _lastError;
  Future<bool>? _inflight;

  AmapInitStatus get status => _status;

  /// 最近一次初始化失败的原因（给 UI 横幅/诊断展示用）。
  String? get lastError => _lastError;

  bool get isReady => _status == AmapInitStatus.ready;

  /// 确保已用 [keyId] 对应的 Key 完成初始化。
  ///
  /// [runner] 执行真正的插件初始化，返回是否成功（内部异常由本方法
  /// 捕获并记录到 [lastError]，不向上抛）。
  Future<bool> ensure(String keyId, Future<bool> Function() runner) {
    if (_status == AmapInitStatus.ready && _activeKeyId == keyId) {
      return Future.value(true);
    }
    final inflight = _inflight;
    if (inflight != null && _activeKeyId == keyId) return inflight;

    _activeKeyId = keyId;
    _status = AmapInitStatus.initializing;
    _lastError = null;
    final future = () async {
      try {
        final ok = await runner();
        if (_activeKeyId != keyId) return false; // 期间 Key 又变了，结果作废
        _status = ok ? AmapInitStatus.ready : AmapInitStatus.failed;
        if (!ok) _lastError = '插件初始化返回失败（无具体原因）';
        return ok;
      } catch (e) {
        if (_activeKeyId == keyId) {
          _status = AmapInitStatus.failed;
          _lastError = e.toString();
        }
        return false;
      } finally {
        if (_activeKeyId == keyId) _inflight = null;
      }
    }();
    _inflight = future;
    return future;
  }

  /// runner 内部已捕获错误细节时，用它覆盖笼统的失败原因。
  void recordError(String message) {
    if (_status == AmapInitStatus.failed) _lastError = message;
  }

  /// 完全复位（Key 被清空等场景）。
  void reset() {
    _status = AmapInitStatus.idle;
    _activeKeyId = null;
    _lastError = null;
    _inflight = null;
  }
}

enum AmapInitStatus { idle, initializing, ready, failed }
