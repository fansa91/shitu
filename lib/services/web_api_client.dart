import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// 三家 Web API 共用的 GET 客户端：统一 8 秒超时与中文错误映射。
/// [client] 可注入（测试 / 后续替换），默认用包级默认客户端。
class WebApiClient {
  WebApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration timeout = Duration(seconds: 8);

  /// GET 并把响应体解码为 JSON 对象；任何失败都转成 [MapApiException]。
  Future<Map<String, dynamic>> getJson(Uri uri, {required String providerName}) async {
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw MapApiException(
        MapApiErrorKind.network,
        '$providerName请求超时（8 秒），请检查网络后重试',
      );
    } catch (e) {
      throw MapApiException(
        MapApiErrorKind.network,
        '$providerName网络请求失败：$e',
      );
    }
    if (response.statusCode != 200) {
      throw MapApiException(
        MapApiErrorKind.network,
        '$providerName服务器返回 HTTP ${response.statusCode}',
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const FormatException('顶层不是 JSON 对象');
    } catch (_) {
      throw MapApiException(
        MapApiErrorKind.parse,
        '$providerName响应解析失败',
      );
    }
  }
}
