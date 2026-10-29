/// 地图 Web API 错误的统一类型：UI 层只需展示 [message]（中文）。
enum MapApiErrorKind {
  /// Key 无效 / 未开通服务等鉴权问题。
  auth,

  /// 配额耗尽 / 频率超限。
  quota,

  /// 网络异常或超时。
  network,

  /// 服务商返回的其它业务错误。
  server,

  /// 响应解析失败。
  parse,

  /// 业务前置条件不满足（如起点无坐标）。
  precondition,
}

class MapApiException implements Exception {
  const MapApiException(this.kind, this.message);

  final MapApiErrorKind kind;
  final String message;

  @override
  String toString() => message;
}
