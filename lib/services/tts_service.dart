import 'dart:async';

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

/// TTS 不可用 / 播报被引擎拒绝：带面向用户的中文原因。
/// UI 层（试听、导航语音按钮）应捕获并展示给用户，禁止静默吞掉。
class TtsUnavailableException implements Exception {
  const TtsUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// 系统 TTS 探活结果（[SystemTtsService.probe]）。
class TtsReadiness {
  const TtsReadiness({required this.available, this.warning, this.error});

  /// 是否能播报（降级可用也为 true，细节看 [warning]）。
  final bool available;

  /// 可用但有明确问题（如缺中文语音数据、已回落默认语言）时的中文说明。
  final String? warning;

  /// 不可用原因（available=false 时非空），面向用户的中文文案。
  final String? error;
}

/// 系统 TTS：flutter_tts 调设备自带语音引擎（离线可用）。
///
/// v0.2 真机「完全无声」后重写（旧版把所有错误吞进 debugPrint）：
/// - 首次使用先 [probe] 探活：查引擎列表与 zh-CN 语音数据可用性，
///   单飞缓存；引擎异步绑定未完成时 speak 会被插件挂起/丢弃，
///   因此 speak 必须等 probe 完成后再发；
/// - zh-CN 语音数据缺失（国际版 OxygenOS 的 Google TTS 常见）时
///   回落引擎默认语言，并把情况写进 [TtsReadiness.warning]，
///   不再假装 setLanguage 成功；
/// - 平台错误经 setErrorHandler 记录，speak 失败抛
///   [TtsUnavailableException] 冒泡到 UI，不再静默。
class SystemTtsService implements TtsService {
  SystemTtsService();

  FlutterTts? _tts;
  Future<TtsReadiness>? _probeFuture;
  TtsReadiness? _readiness;
  String? _lastPlatformError;

  @override
  TtsEngine get engine => TtsEngine.system;

  /// 探活是否已完成且可用（同步快照，未探活时为 false）。
  bool get isReady => _readiness?.available ?? false;

  /// 平台错误回调最近一次报告的内容（诊断用）。
  String? get lastPlatformError => _lastPlatformError;

  /// 首次使用时探活：引擎存在性 + zh-CN 可用性 + 基础参数设置。
  /// 结果缓存，重复调用直接返回同一 Future。
  Future<TtsReadiness> probe() => _probeFuture ??= _doProbe();

  Future<TtsReadiness> _doProbe() async {
    try {
      final tts = _tts ??= FlutterTts();
      tts.setErrorHandler((msg) => _lastPlatformError = msg);

      // 引擎列表：服务绑定是异步的，刚 attach 时可能短暂为空，隔 600ms 重试一次，
      // 避免把「还没绑好」误判成「没装引擎」。
      var engines = await _enginesOrNull(tts);
      if (engines != null && engines.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        engines = await _enginesOrNull(tts);
      }
      if (engines != null && engines.isEmpty) {
        return _readiness = const TtsReadiness(
          available: false,
          error: '未检测到可用的语音合成引擎：请到系统设置 → 语言与输入法 → '
              '文本转语音输出 中安装或启用一个 TTS 引擎',
        );
      }

      // 语言：优先 zh-CN；缺中文语音数据时回落默认语言并给出明确警告。
      var zhAvailable = false;
      try {
        zhAvailable = await tts.isLanguageAvailable('zh-CN') == true;
      } catch (_) {}
      String? warning;
      if (zhAvailable) {
        try {
          await tts.setLanguage('zh-CN');
        } catch (_) {}
      } else {
        warning = '未检测到中文语音数据，将使用引擎默认语言播报，中文可能读不出声。'
            '请到系统设置 → 文本转语音输出 → 语音引擎设置 中安装中文语音包';
        // 不指定语言：保持引擎默认语言（插件 onInit 已设为默认 voice 语言）。
      }
      try {
        await tts.setVolume(1.0);
      } catch (_) {}
      try {
        await tts.setSpeechRate(1.0);
      } catch (_) {}
      try {
        await tts.setPitch(1.0);
      } catch (_) {}
      return _readiness = TtsReadiness(available: true, warning: warning);
    } catch (e) {
      return _readiness = TtsReadiness(
        available: false,
        error: '语音引擎初始化失败：$e',
      );
    }
  }

  Future<List<dynamic>?> _enginesOrNull(FlutterTts tts) async {
    try {
      final result = await tts.getEngines;
      return result is List ? result : null;
    } catch (_) {
      return null; // 拿不到列表（如桌面端）不据此判死，继续后面的语言检查
    }
  }

  @override
  Future<void> speak(String text) async {
    final readiness = await probe();
    if (!readiness.available) {
      throw TtsUnavailableException(readiness.error ?? '语音不可用');
    }
    _lastPlatformError = null;
    final result = await _tts!.speak(text);
    if (_lastPlatformError != null) {
      throw TtsUnavailableException('语音播报失败：$_lastPlatformError');
    }
    // 插件约定：返回 0 表示这句被丢弃（如引擎正忙且队列被冲掉）。
    if (result is int && result == 0) {
      throw const TtsUnavailableException(
        '这句播报未被语音引擎接受（引擎忙或缺少语音数据），请检查系统 TTS 设置',
      );
    }
  }

  /// 试听专用：播一句并等它真正播完/报错/超时，让设置页能给出确定反馈。
  /// 返回 null 表示正常播完；返回字符串为失败/不确定原因。
  Future<String?> speakAndWait(
    String text, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final readiness = await probe();
    if (!readiness.available) return readiness.error ?? '语音不可用';
    final tts = _tts!;
    final completer = Completer<String?>();
    tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete(null);
    });
    tts.setErrorHandler((msg) {
      _lastPlatformError = msg;
      if (!completer.isCompleted) completer.complete('语音播报失败：$msg');
    });
    try {
      await speak(text);
    } on TtsUnavailableException catch (e) {
      return e.reason;
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () => '已把试听句发给语音引擎，但没等到播完回执；'
          '若仍无声，请检查媒体音量与系统 TTS 引擎设置',
    );
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
