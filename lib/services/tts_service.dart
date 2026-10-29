import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/map_provider.dart';

/// 英伟达 Magpie TTS Multilingual 的 zh-CN 音色（设置页可选，默认 Siwei）。
const nvidiaVoiceNames = <String>[
  'Siwei',
  'HouZhen',
  'Long',
  'Diego',
  'Isabela',
  'Jason',
  'Louise',
  'Pascal',
];

/// 音色短名 → Magpie 完整 voice id。
String magpieVoiceId(String name) => 'Magpie-Multilingual.ZH-CN.$name';

/// 语音播报抽象。导航页只依赖此接口，引擎可切换。
abstract class TtsService {
  TtsEngine get engine;
  Future<void> speak(String text);
  Future<void> stop();
}

/// 系统 TTS：flutter_tts 调设备自带语音引擎（离线可用）。
class SystemTtsService implements TtsService {
  SystemTtsService();

  FlutterTts? _tts;
  bool _languageSet = false;

  @override
  TtsEngine get engine => TtsEngine.system;

  Future<FlutterTts> _ensure() async {
    final tts = _tts ??= FlutterTts();
    if (!_languageSet) {
      _languageSet = true;
      try {
        await tts.setLanguage('zh-CN');
      } catch (_) {
        // 个别设备无中文语音包时保持引擎默认语言，不阻断播报。
      }
    }
    return tts;
  }

  @override
  Future<void> speak(String text) async {
    try {
      final tts = await _ensure();
      await tts.speak(text);
    } catch (e) {
      debugPrint('[TTS-系统] 播报失败：$e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}

/// 英伟达合成不可用（协议层未打通 / 无 Key / 网络失败等），带面向用户的中文原因。
class NvidiaTtsUnavailable implements Exception {
  const NvidiaTtsUnavailable(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// 语音合成器抽象：文本 → WAV 字节。英伟达路径的实现点。
abstract class SpeechSynthesizer {
  Future<List<int>> synthesize(String text);
}

/// 当前内置的英伟达合成器：**未打通**。
///
/// 卡点（如实记录）：Magpie TTS 只提供 gRPC（Riva 协议，
/// grpc.nvcf.nvidia.com:443），Dart 侧没有官方 Riva 客户端，
/// 需要 .proto 生成代码随包发布，本版本未内置该生成层；
/// 且无法在无真实 Key 的约束下验证协议正确性。
/// 因此本实现一律抛 [NvidiaTtsUnavailable]，由 [NvidiaTtsService]
/// 明确回落系统 TTS 并向上层报告原因，绝不假装合成成功。
class RivaSpeechSynthesizer implements SpeechSynthesizer {
  const RivaSpeechSynthesizer({required this.apiKey, required this.voice});

  final String apiKey;
  final String voice;

  /// NVCF 上 Magpie TTS Multilingual 的 function-id（协议打通后使用）。
  static const functionId = '877104f7-e885-42b9-8de8-f6e4c6303969';
  static const endpoint = 'grpc.nvcf.nvidia.com:443';

  @override
  Future<List<int>> synthesize(String text) async {
    if (apiKey.trim().isEmpty) {
      throw const NvidiaTtsUnavailable('未填写英伟达 TTS Key');
    }
    throw const NvidiaTtsUnavailable(
      '英伟达合成协议层（Riva gRPC）尚未接入本版本，已回落系统语音',
    );
  }
}

/// 预合成结果报告。
class PresynthReport {
  const PresynthReport({required this.available, this.reason});

  final bool available;
  final String? reason;
}

/// 英伟达 TTS：算路后预合成全部播报文案，导航时播合成音频；
/// 合成不可用/失败时**明确回落系统 TTS**（[lastFallbackReason] 记录原因）。
class NvidiaTtsService implements TtsService {
  NvidiaTtsService({
    required this.apiKey,
    required this.voice,
    SpeechSynthesizer? synthesizer,
    TtsService? fallback,
  })  : _synthesizer = synthesizer ??
            RivaSpeechSynthesizer(apiKey: apiKey, voice: voice),
        _fallback = fallback ?? SystemTtsService();

  final String apiKey;
  final String voice;
  final SpeechSynthesizer _synthesizer;
  final TtsService _fallback;

  /// 最近一次回落系统语音的原因（null = 未发生回落）。UI 据此如实提示。
  String? lastFallbackReason;

  @override
  TtsEngine get engine => TtsEngine.nvidia;

  /// 预合成：先用第一条文案探活。不可用则整体报告不可用（不逐条硬试）。
  Future<PresynthReport> presynthesize(List<String> texts) async {
    if (texts.isEmpty) return const PresynthReport(available: true);
    try {
      await _synthesizer.synthesize(texts.first);
      // 探活成功也暂不落盘缓存：当前内置合成器不可用，此分支为协议
      // 打通后的扩展点；在那之前 speak() 仍会逐条回落并报告。
      return const PresynthReport(
        available: false,
        reason: '合成音频播放组件未接入，已回落系统语音',
      );
    } on NvidiaTtsUnavailable catch (e) {
      lastFallbackReason = e.reason;
      return PresynthReport(available: false, reason: e.reason);
    } catch (e) {
      lastFallbackReason = '英伟达合成失败：$e';
      return PresynthReport(available: false, reason: lastFallbackReason);
    }
  }

  @override
  Future<void> speak(String text) async {
    try {
      await _synthesizer.synthesize(text);
      // 合成出字节但当前无音频播放组件接入：如实回落，不假装已播合成音。
      lastFallbackReason = '合成音频播放组件未接入，已回落系统语音';
    } on NvidiaTtsUnavailable catch (e) {
      lastFallbackReason = e.reason;
    } catch (e) {
      lastFallbackReason = '英伟达合成失败：$e';
    }
    await _fallback.speak(text);
  }

  @override
  Future<void> stop() => _fallback.stop();
}

/// 按设置创建对应的 TTS 服务。
TtsService createTtsService({
  required TtsEngine engine,
  required String nvidiaKey,
  String nvidiaVoice = 'Siwei',
}) {
  return switch (engine) {
    TtsEngine.system => SystemTtsService(),
    TtsEngine.nvidia => NvidiaTtsService(
        apiKey: nvidiaKey,
        voice: magpieVoiceId(nvidiaVoice),
      ),
  };
}
