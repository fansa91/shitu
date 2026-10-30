import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/geo_point.dart';
import '../models/located_fix.dart';
import '../models/map_provider.dart';
import '../theme/appearance.dart';
import '../utils/external_link.dart';
import '../utils/format.dart';
import '../services/api_exception.dart';
import '../services/app_signature_service.dart';
import '../services/location_guard.dart';
import '../services/location_runtime_status.dart';
import '../services/location_service.dart';
import '../services/map_data_services.dart';
import '../services/native_map_probe.dart';
import '../services/map_tiles.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';

/// 设置页：数据源单选、Key 管理（用户自填）、申请指南、语音、关于。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings});

  final SettingsService settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  /// 固定发布 keystore 的证书 SHA1 指纹（公开值，非密码）：与仓库 Secrets
  /// 中 ANDROID_KEYSTORE_BASE64 对应的那把钥匙一致，换钥匙时同步更新这里。
  static const _releaseSha1 =
      '60:15:40:F1:35:0A:61:37:F5:3E:6E:1C:C6:A3:1F:92:55:DA:F8:5D';
  static const _packageName = 'com.shitu.app';

  final Map<MapProvider, TextEditingController> _keyControllers = {};
  final _nvidiaController = TextEditingController();
  final _amapSdkController = TextEditingController();
  final _amapIosSdkController = TextEditingController();

  /// 高德定位崩溃守卫（与定位服务共用同一份存储，见 location_guard.dart）。
  final _locationGuard = AmapLocationGuard();
  bool _locationGuardTripped = false;

  /// 原生地图探针（仅 Android）：留痕读取 + 打开探针页。
  final _probe = NativeMapProbeService();
  ProbeStatus? _probeStatus;
  final Map<String, String> _testResults = {};
  final Set<String> _testing = {};

  SettingsService get _settings => widget.settings;

  @override
  void initState() {
    super.initState();
    for (final p in MapProvider.values) {
      _keyControllers[p] = TextEditingController(text: _settings.keyFor(p));
    }
    _nvidiaController.text = _settings.nvidiaKey;
    _amapSdkController.text = _settings.amapSdkAndroidKey;
    _amapIosSdkController.text = _settings.amapSdkIosKey;
    _loadVersion();
    _loadRuntimeSignature();
    _loadGuardState();
    WidgetsBinding.instance.addObserver(this);
    _loadProbeStatus();
  }

  /// 从探针页返回（或崩溃后重启回到设置页）时刷新探针留痕判读。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadProbeStatus();
  }

  Future<void> _loadProbeStatus() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final status = await _probe.lastStatus();
    if (!mounted) return;
    setState(() => _probeStatus = status);
  }

  /// 打开原生地图探针页：先过前置条件（Key + 隐私同意），再尽力取
  /// 当前定位作为探针页的落点（取不到不拦，原生侧用默认点）。
  Future<void> _openProbe() async {
    final blocker = probeBlocker(
      hasSdkKey: _settings.hasAmapSdkAndroidKey,
      privacyAgreed: _settings.privacyAgreed,
    );
    if (blocker == ProbeBlocker.missingKey) {
      _snack('请先在上方「高德 SDK Key」卡填写 Android SDK Key');
      return;
    }
    if (blocker == ProbeBlocker.privacyNotAgreed) {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('同意高德隐私政策'),
          content: const Text(
            '原生地图探针使用高德地图 SDK，需先同意高德隐私政策'
            '（与高德定位共用同一份同意，就是上方那个开关）。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('同意并打开'),
            ),
          ],
        ),
      );
      if (agreed != true || !mounted) return;
      await _settings.setPrivacyAgreed(true);
    }
    GeoPoint? target;
    try {
      final fix = await LocationService(settings: _settings)
          .currentFix()
          .timeout(const Duration(seconds: 5));
      target = fix.point;
    } catch (_) {
      // 定位失败不拦探针：原生侧会用天安门默认点。
      target = null;
    }
    try {
      await _probe.open(apiKey: _settings.amapSdkAndroidKey, target: target);
    } on PlatformException catch (e) {
      _snack('打开探针页失败：${e.message ?? e.code}');
    }
  }

  Future<void> _loadGuardState() async {
    final tripped = await _locationGuard.isTripped();
    if (!mounted) return;
    setState(() => _locationGuardTripped = tripped);
  }

  /// 试听专用系统 TTS 实例（独立于导航页的实例，探活结果可复用）。
  final _previewTts = SystemTtsService();

  /// 「关于」版本号：运行时读构建信息（pubspec / CI tag 注入），不在代码里写死。
  String? _versionText;

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(
        () => _versionText = formatAppVersion(info.version, info.buildNumber),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionText = '版本未知');
    }
  }

  /// 本机运行时签名 SHA1（原生通道读取实际安装包的证书）：
  /// 与代码里预期的发布 SHA1 对照，即可判断高德控制台该填哪个值。
  String? _runtimeSha1;
  String? _signatureNote = '读取中…';

  Future<void> _loadRuntimeSignature() async {
    final result = await AppSignatureService().fetchSha1();
    if (!mounted) return;
    setState(() {
      _runtimeSha1 = result.sha1;
      _signatureNote = result.error;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _keyControllers.values) {
      c.dispose();
    }
    _nvidiaController.dispose();
    _amapSdkController.dispose();
    _amapIosSdkController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 「测试连接」：已填 Web Key → 发一次轻量真实请求（地理编码）验活；
  /// 未填时维持本地格式校验文案。
  Future<void> _testProviderKey(MapProvider provider) async {
    final id = provider.name;
    final value = _keyControllers[provider]!.text.trim();
    if (value.isEmpty) {
      _testLocalFormat(id, value);
      return;
    }
    setState(() {
      _testing.add(id);
      _testResults[id] = '正在请求${provider.displayName}验活…';
    });
    final service = createRealMapDataService(provider, key: value);
    try {
      final message = await service!.testConnection();
      if (mounted) setState(() => _testResults[id] = message);
    } on MapApiException catch (e) {
      if (mounted) setState(() => _testResults[id] = '连接失败：${e.message}');
    } catch (_) {
      if (mounted) setState(() => _testResults[id] = '连接失败：未知错误');
    } finally {
      if (mounted) setState(() => _testing.remove(id));
    }
  }

  /// 本地格式校验（未填 Key / 英伟达卡使用，不发起真实请求）。
  void _testLocalFormat(String id, String value) {
    final v = value.trim();
    final String result;
    if (v.isEmpty) {
      result = '未填写';
    } else if (v.length < 8) {
      result = '格式不正确：长度过短（本地校验）';
    } else {
      result = '本地格式校验通过（骨架阶段，未发起真实请求）';
    }
    setState(() => _testResults[id] = result);
  }

  /// 试听：先探活系统 TTS（无引擎/缺中文语音数据都要让用户看见原因，
  /// 不再无声失败）；英伟达引擎先走预合成探活，不可用则明确提示原因
  /// 并回落系统语音试听（不假装是英伟达音色在播）。
  Future<void> _previewVoice() async {
    const sample = '前方三百米右转，进入深南大道';
    final readiness = await _previewTts.probe();
    if (!mounted) return;
    if (!readiness.available) {
      _snack('语音不可用：${readiness.error}');
      return;
    }
    if (_settings.ttsEngine == TtsEngine.system) {
      await _speakPreviewSample(sample, readiness);
      return;
    }
    final service = NvidiaTtsService(
      apiKey: _settings.nvidiaKey,
      voice: _settings.nvidiaVoice,
      fallback: _previewTts,
    );
    final report = await service.presynthesize(const [sample]);
    if (!mounted) return;
    if (report.available) {
      await service.speak(sample);
      return;
    }
    _snack('英伟达合成暂不可用：${report.reason}。下面用系统语音试听');
    await _speakPreviewSample(sample, readiness);
  }

  /// 系统语音试听（含英伟达回落）：等播完/报错才给反馈；
  /// 中文语音数据缺失时改播一句英文确认引擎本身能出声。
  Future<void> _speakPreviewSample(
    String sample,
    TtsReadiness readiness,
  ) async {
    if (readiness.warning != null) {
      _snack(readiness.warning!);
      await _previewTts.speakAndWait(
        'Voice test. The speech engine is working.',
        timeout: const Duration(seconds: 6),
      );
      return;
    }
    final result = await _previewTts.speakAndWait(sample);
    if (!mounted) return;
    _snack(result ?? '试听完成（系统语音）');
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _snack('已复制：$text');
  }

  /// 打开「获取 Key」控制台外链，失败时提示手动访问。
  Future<void> _openGetKey(String url) async {
    final ok = await openExternalUrl(url);
    if (!ok && mounted) {
      _snack('打开链接失败，请手动在浏览器访问：$url');
    }
  }

  /// Key 卡下方的「获取 Key →」外链文字按钮。
  Widget _getKeyButton(String url) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _openGetKey(url),
        icon: const Icon(Icons.open_in_new, size: 16),
        label: const Text('获取 Key'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('设置')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _sectionTitle('数据源'),
              Card(
                child: RadioGroup<MapProvider>(
                  groupValue: _settings.provider,
                  onChanged: (value) {
                    if (value != null) _settings.setProvider(value);
                  },
                  child: Column(
                    children: [
                      for (final p in MapProvider.values)
                        RadioListTile<MapProvider>(
                          value: p,
                          title: Text(p.displayName),
                          subtitle: Text(
                            _settings.hasKeyFor(p) ? 'Key 已填写' : 'Key 未填写',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _sectionTitle('外观'),
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Text(
                        '主题模式',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: SegmentedButton<AppThemeMode>(
                        segments: [
                          for (final m in AppThemeMode.values)
                            ButtonSegment<AppThemeMode>(
                              value: m,
                              label: Text(m.label),
                            ),
                        ],
                        selected: {_settings.themeMode},
                        onSelectionChanged: (s) =>
                            _settings.setThemeMode(s.first),
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('动态取色'),
                      subtitle: const Text(
                        '跟随系统壁纸配色（Android 12+）；系统无动态配色时使用下方主题色',
                      ),
                      value: _settings.dynamicColorEnabled,
                      onChanged: _settings.setDynamicColorEnabled,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                      child: Text(
                        '主题色',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          for (final opt in seedOptions) _seedSwatch(opt),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _sectionTitle('API Key 管理（用户自填）'),
              for (final p in MapProvider.values)
                _keyCard(
                  id: p.name,
                  title: p.keyLabel,
                  controller: _keyControllers[p]!,
                  filled: _settings.hasKeyFor(p),
                  getKeyUrl: KeyConsoleUrls.forProvider(p),
                  onSave: () async {
                    await _settings.setKeyFor(p, _keyControllers[p]!.text);
                    _snack('${p.keyLabel} 已保存（Web Key 即时生效）');
                  },
                  onTest: () => _testProviderKey(p),
                ),
              _sectionTitle('地图'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '底图来源',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<MapTileSource>(
                        segments: [
                          for (final src in MapTileSource.values)
                            ButtonSegment<MapTileSource>(
                              value: src,
                              label: Text(src.label),
                            ),
                        ],
                        selected: {_settings.mapTileSource},
                        onSelectionChanged: (s) =>
                            _settings.setMapTileSource(s.first),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '底图样式',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<MapBaseStyle>(
                        segments: [
                          for (final st in MapBaseStyle.values)
                            ButtonSegment<MapBaseStyle>(
                              value: st,
                              label: Text(st.label),
                            ),
                        ],
                        selected: {_settings.mapBaseStyle},
                        onSelectionChanged: (s) =>
                            _settings.setMapBaseStyle(s.first),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          '以下图源/样式适用于安卓/桌面的瓦片底图'
                          '（iOS 用原生高德地图，见下方「高德 SDK Key」）。'
                          '瓦片为 Web 图（2D 平面图），不需要填 Key、无 3D '
                          '倾斜与建筑。高德卫星叠加路网标注、路况图层仅高德'
                          '源可用；腾讯卫星只有影像、无标注与路况图层。',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _sectionTitle('高德定位'),
              _sdkKeysCard(),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '定位源',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<LocationSourceMode>(
                        segments: [
                          for (final m in LocationSourceMode.values)
                            ButtonSegment<LocationSourceMode>(
                              value: m,
                              label: Text(m.label),
                            ),
                        ],
                        selected: {_settings.locationSourceMode},
                        onSelectionChanged: (s) =>
                            _settings.setLocationSourceMode(s.first),
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('同意高德隐私政策'),
                        subtitle: const Text(
                          '使用高德定位与 iOS 原生地图前必须同意；未同意时'
                          '不会初始化高德定位 SDK、iOS 也不启用原生地图。',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _settings.privacyAgreed,
                        onChanged: (v) => _settings.setPrivacyAgreed(v),
                      ),
                      const Divider(height: 8),
                      ListenableBuilder(
                        listenable: LocationRuntimeStatus.instance,
                        builder: (context, _) {
                          final status = LocationRuntimeStatus.instance;
                          final active = status.activeSource;
                          final accuracy = status.lastAccuracyMeters;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                active == null
                                    ? '当前生效定位源：尚未定位'
                                    : '当前生效定位源：${active.label}'
                                          '${status.note == null ? '' : '（${status.note}）'}',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                              if (accuracy != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '最近一次定位精度：±${accuracy.toStringAsFixed(0)} 米'
                                    '（来源：${status.lastFixSource?.label ?? '—'}）',
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      if (_locationGuardTripped) ...[
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '上次启动高德定位时进程异常结束，守卫已自动跳过高德定位。'
                            '如判断是误报，可手动重试一次。',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () async {
                              await _locationGuard.resetByUser();
                              LocationRuntimeStatus.instance.reportNote(null);
                              await _loadGuardState();
                              _snack('已复位守卫，下次定位将重新尝试高德');
                            },
                            child: const Text('重试高德定位'),
                          ),
                        ),
                      ],
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          '高德定位仅 Android 可用：直接给出 GCJ-02 坐标，'
                          '国内 WiFi/基站定位比系统定位快；iOS 与桌面端'
                          '自动使用系统定位。自动模式下高德失败或首定超时'
                          '（约 8 秒）会自动回落系统定位。',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 原生地图探针入口（仅 Android）：原生 Activity 直挂
              // TextureMapView 并跑在独立进程，与瓦片底图是两条完全
              // 独立的路径，只为验证原生高德地图能否在本机出图。
              if (defaultTargetPlatform == TargetPlatform.android)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.science_outlined),
                    title: const Text('原生地图探针（实验 · 导航 SDK 9.8.3 · 独立进程）'),
                    subtitle: Text(
                      _probeStatus == null
                          ? '读取中…'
                          : probeStatusText(_probeStatus!),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openProbe,
                  ),
                ),
              _keyCard(
                id: 'nvidia',
                title: '英伟达 TTS Key（可选）',
                controller: _nvidiaController,
                filled: _settings.nvidiaKey.isNotEmpty,
                getKeyUrl: KeyConsoleUrls.nvidia,
                onSave: () async {
                  await _settings.setNvidiaKey(_nvidiaController.text);
                  _snack('英伟达 TTS Key 已保存');
                },
              ),
              _sectionTitle('申请指南'),
              Card(
                child: ExpansionTile(
                  title: const Text('如何申请各家 Key'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '到对应开放平台控制台创建应用时，包名 / Bundle ID 填右边的值，'
                        'Android 还需填发布签名 SHA1。',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                    _copyRow('包名 / Bundle ID', _packageName),
                    _copyRow('发布 SHA1（预期）', _releaseSha1),
                    if (_runtimeSha1 != null)
                      _copyRow('本机运行时 SHA1', _runtimeSha1!)
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '本机运行时 SHA1：${_signatureNote ?? '读取失败'}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '创建应用时若控制台要求填签名，填「本机运行时 SHA1」：'
                        '它来自实际安装包的签名证书。'
                        '若它与上方发布 SHA1 不同，说明当前装的不是正式签名包。',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              _sectionTitle('语音播报'),
              Card(
                child: Column(
                  children: [
                    RadioGroup<TtsEngine>(
                      groupValue: _settings.ttsEngine,
                      onChanged: (value) {
                        if (value != null) _settings.setTtsEngine(value);
                      },
                      child: Column(
                        children: [
                          for (final e in TtsEngine.values)
                            RadioListTile<TtsEngine>(
                              value: e,
                              title: Text(e.displayName),
                              subtitle: e == TtsEngine.nvidia
                                  ? const Text('路线预合成缓存播报，断网回落系统语音')
                                  : const Text('设备自带语音，离线可用'),
                            ),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('预合成路线播报'),
                      subtitle: const Text('算路后提前合成全部播报文案（英伟达引擎）'),
                      value: _settings.ttsPresynthesize,
                      onChanged: _settings.setTtsPresynthesize,
                    ),
                    if (_settings.ttsEngine == TtsEngine.nvidia)
                      ListTile(
                        title: const Text('英伟达音色'),
                        subtitle: const Text('Magpie 中文音色，预合成时使用'),
                        trailing: DropdownButton<String>(
                          value: _settings.nvidiaVoice,
                          items: [
                            for (final name in nvidiaVoiceNames)
                              DropdownMenuItem(value: name, child: Text(name)),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              _settings.setNvidiaVoice(value);
                            }
                          },
                        ),
                      ),
                    ListTile(
                      leading: const Icon(Icons.play_circle_outline),
                      title: const Text('试听'),
                      subtitle: const Text('前方三百米右转，进入深南大道'),
                      onTap: _previewVoice,
                    ),
                  ],
                ),
              ),
              _sectionTitle('关于'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('识途'),
                      subtitle: Text(_versionText ?? '版本加载中…'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 主题色圆形色板：选中态为对勾 + 主色描边，点击即存即生效。
  Widget _seedSwatch(SeedOption opt) {
    final selected = _settings.seedColorValue == opt.color.toARGB32();
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: opt.name,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _settings.setSeedColor(opt.color),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: opt.color,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 20)
              : null,
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _copyRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text('$label：$value', style: const TextStyle(fontSize: 12.5)),
        ),
        IconButton(
          icon: const Icon(Icons.copy_outlined, size: 18),
          tooltip: '复制',
          onPressed: () => _copy(value),
        ),
      ],
    );
  }

  /// 高德 SDK Key 合并卡：Android Key（供定位）与 iOS Key（供 iOS
  /// 原生地图）同卡管理——两把 Key 在高德控制台同属一个应用，
  /// 绑定信息（包名 / 签名）见下方申请指南。
  Widget _sdkKeysCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('高德 SDK Key', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            _sdkKeyBlock(
              id: 'amap_sdk_android',
              label: 'Android Key（供定位）',
              controller: _amapSdkController,
              filled: _settings.hasAmapSdkAndroidKey,
              onSave: () async {
                await _settings.setAmapSdkAndroidKey(_amapSdkController.text);
                _snack('Android SDK Key 已保存（供高德定位）');
              },
            ),
            const Divider(height: 22),
            _sdkKeyBlock(
              id: 'amap_sdk_ios',
              label: 'iOS Key（供 iOS 原生地图）',
              controller: _amapIosSdkController,
              filled: _settings.hasAmapSdkIosKey,
              onSave: () async {
                await _settings.setAmapSdkIosKey(_amapIosSdkController.text);
                _snack('iOS SDK Key 已保存（供 iOS 原生地图）');
              },
            ),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'iOS 填 Key 并同意下方隐私后使用原生高德地图，'
                '没填则回落瓦片底图。两把 Key 与上方三家 Web Key '
                '（搜索/算路）互不通用，分开申请。',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// SDK Key 卡内的单个 Key 区块（状态点 + 标签 + 密码框 + 保存/
  /// 本地格式测试 + 申请入口），版式与 [_keyCard] 一致。
  Widget _sdkKeyBlock({
    required String id,
    required String label,
    required TextEditingController controller,
    required bool filled,
    required VoidCallback onSave,
  }) {
    final result = _testResults[id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled
                    ? const Color(0xFF34A853)
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              filled ? '已填写' : '未填写',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: '粘贴你申请的 Key',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.tonal(onPressed: onSave, child: const Text('保存')),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _testing.contains(id)
                  ? null
                  : () => _testLocalFormat(id, controller.text),
              child: Text(_testing.contains(id) ? '测试中…' : '测试连接'),
            ),
          ],
        ),
        _getKeyButton(KeyConsoleUrls.forProvider(MapProvider.amap)),
        if (result != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              result,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _keyCard({
    required String id,
    required String title,
    required TextEditingController controller,
    required bool filled,
    required String getKeyUrl,
    required VoidCallback onSave,
    VoidCallback? onTest,
  }) {
    final result = _testResults[id];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? const Color(0xFF34A853)
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  filled ? '已填写' : '未填写',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: '粘贴你申请的 Key',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.tonal(onPressed: onSave, child: const Text('保存')),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _testing.contains(id)
                      ? null
                      : (onTest ?? () => _testLocalFormat(id, controller.text)),
                  child: Text(_testing.contains(id) ? '测试中…' : '测试连接'),
                ),
              ],
            ),
            _getKeyButton(getKeyUrl),
            if (result != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  result,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
