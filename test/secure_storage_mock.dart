import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// flutter_secure_storage 的方法通道内存 mock（供设置类测试共用）。
/// 返回后备 Map，测试可直接断言安全存储里存了什么。
Map<String, String> installSecureStorageMock() {
  final store = <String, String>{};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
    final key = args['key']?.toString() ?? '';
    switch (call.method) {
      case 'read':
        return store[key];
      case 'write':
        store[key] = args['value']?.toString() ?? '';
        return null;
      case 'delete':
        store.remove(key);
        return null;
      case 'deleteAll':
        store.clear();
        return null;
      case 'readAll':
        return Map<String, String>.from(store);
      case 'containsKey':
        return store.containsKey(key);
      default:
        return null;
    }
  });
  return store;
}
