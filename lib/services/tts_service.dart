import 'package:flutter/foundation.dart';

import '../models/map_provider.dart';

/// 语音播报抽象。导航页只依赖此接口，引擎可切换。
abstract class TtsService {
  TtsEngine get engine;
  Future<void> speak(String text);
  Future<void> stop();
}

/// 系统 TTS 桩实现（骨架阶段不接 flutter_tts，仅记录日志）。
class SystemTtsServiceStub implements TtsService {
  const SystemTtsServiceStub();

  @override
  TtsEngine get engine => TtsEngine.system;

  @override
  Future<void> speak(String text) async {
    // TODO: 接入系统 TTS（flutter_tts）后在此播报。
    debugPrint('[TTS-系统-桩] $text');
  }

  @override
  Future<void> stop() async {}
}

/// 英伟达 TTS 桩实现。
///
/// 设计：算路完成后把全部播报文案预合成并缓存，导航时播本地文件；
/// 本桩不发起任何真实网络请求（不调 build.nvidia.com 的 gRPC 端点）。
class NvidiaTtsServiceStub implements TtsService {
  const NvidiaTtsServiceStub({required this.apiKey});

  /// 用户在设置页自填的 NVIDIA API Key（nvapi-…），可为空。
  final String apiKey;

  @override
  TtsEngine get engine => TtsEngine.nvidia;

  @override
  Future<void> speak(String text) async {
    // TODO: 走预合成缓存播报；缓存未命中/断网时由调用方回落系统 TTS。
    debugPrint('[TTS-英伟达-桩] $text');
  }

  @override
  Future<void> stop() async {}
}

/// 按设置创建对应的 TTS 服务。
TtsService createTtsService({
  required TtsEngine engine,
  required String nvidiaKey,
}) {
  return switch (engine) {
    TtsEngine.system => const SystemTtsServiceStub(),
    TtsEngine.nvidia => NvidiaTtsServiceStub(apiKey: nvidiaKey),
  };
}
