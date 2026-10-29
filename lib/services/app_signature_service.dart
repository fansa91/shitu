import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 读取本应用在当前设备上的**运行时签名证书 SHA1**（仅 Android）。
///
/// 用途：高德控制台给 Android Key 绑定的包名/SHA1 必须与实际安装包的
/// 签名一致，否则 SDK 鉴权失败。发布签名 SHA1 是代码里写死的预期值，
/// 设备上实际装的包（CI 临时自签、本地调试签等）签名可能不同——
/// 把运行时真值显示出来，用户才能与控制台登记值逐字对照。
/// 原生实现见 MainActivity 的 `com.shitu.app/signature` 通道。
class AppSignatureService {
  AppSignatureService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.shitu.app/signature';

  final MethodChannel _channel;

  /// 原始 hex（可带分隔符/空白、大小写不限）→ 高德控制台要求的格式：
  /// 大写、每字节两位、冒号分隔。非法输入（非 40 位 hex）返回 null。
  static String? formatSha1Hex(String? hex) {
    if (hex == null) return null;
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    if (clean.length != 40) return null; // SHA-1 = 20 字节 = 40 个 hex 字符
    return [
      for (var i = 0; i < clean.length; i += 2) clean.substring(i, i + 2),
    ].join(':');
  }

  /// 取运行时签名 SHA1。取不到不抛异常：sha1 为 null、error 给原因，
  /// UI 直接展示原因即可（签名读不到不该影响任何功能）。
  Future<({String? sha1, String? error})> fetchSha1() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return (sha1: null, error: '仅 Android 需要签名 SHA1，本平台不适用');
    }
    try {
      final hex = await _channel.invokeMethod<String>('getSigningSha1Hex');
      final formatted = formatSha1Hex(hex);
      if (formatted == null) {
        return (sha1: null, error: '原生侧未返回有效签名（返回为空或格式不对）');
      }
      return (sha1: formatted, error: null);
    } on PlatformException catch (e) {
      return (sha1: null, error: '读取签名失败：${e.message ?? e.code}');
    } on MissingPluginException {
      return (sha1: null, error: '签名通道未注册（原生实现缺失）');
    } catch (e) {
      return (sha1: null, error: '读取签名失败：$e');
    }
  }
}
