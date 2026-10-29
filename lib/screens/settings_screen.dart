import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/map_provider.dart';
import '../theme/appearance.dart';
import '../utils/external_link.dart';
import '../utils/format.dart';
import '../services/api_exception.dart';
import '../services/map_data_services.dart';
import '../services/settings_service.dart';

/// 设置页：数据源单选、Key 管理（用户自填）、申请指南、语音、关于。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings});

  final SettingsService settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// 固定发布 keystore 的证书 SHA1 指纹（公开值，非密码）：与仓库 Secrets
  /// 中 ANDROID_KEYSTORE_BASE64 对应的那把钥匙一致，换钥匙时同步更新这里。
  static const _releaseSha1 = '60:15:40:F1:35:0A:61:37:F5:3E:6E:1C:C6:A3:1F:92:55:DA:F8:5D';
  static const _packageName = 'com.shitu.app';

  final Map<MapProvider, TextEditingController> _keyControllers = {};
  final _nvidiaController = TextEditingController();
  final _sdkAndroidController = TextEditingController();
  final _sdkIosController = TextEditingController();
  final Map<String, String> _testResults = {};
  final Set<String> _testing = {};

  SettingsService get _settings => widget.settings;

  @override
  void initState() {
    super.initState();
    for (final p in MapProvider.values) {
      _keyControllers[p] =
          TextEditingController(text: _settings.keyFor(p));
    }
    _nvidiaController.text = _settings.nvidiaKey;
    _sdkAndroidController.text = _settings.amapSdkAndroidKey;
    _sdkIosController.text = _settings.amapSdkIosKey;
    _loadVersion();
  }

  /// 「关于」版本号：运行时读构建信息（pubspec / CI tag 注入），不在代码里写死。
  String? _versionText;

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(
          () => _versionText = formatAppVersion(info.version, info.buildNumber));
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionText = '版本未知');
    }
  }

  @override
  void dispose() {
    for (final c in _keyControllers.values) {
      c.dispose();
    }
    _nvidiaController.dispose();
    _sdkAndroidController.dispose();
    _sdkIosController.dispose();
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
                              _settings.hasKeyFor(p) ? 'Key 已填写' : 'Key 未填写'),
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
                      child: Text('主题模式',
                          style: Theme.of(context).textTheme.titleSmall),
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
                          '跟随系统壁纸配色（Android 12+）；系统无动态配色时使用下方主题色'),
                      value: _settings.dynamicColorEnabled,
                      onChanged: _settings.setDynamicColorEnabled,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                      child: Text('主题色',
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          for (final opt in seedOptions)
                            _seedSwatch(opt),
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
              _amapSdkCard(),
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
                  childrenPadding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
                    _copyRow('发布 SHA1', _releaseSha1),
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
                  ],
                ),
              ),
              _sectionTitle('关于'),
              Card(
                child: ListTile(
                  title: const Text('识途'),
                  subtitle: Text(_versionText ?? '版本加载中…'),
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
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _copyRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text('$label：$value',
              style: const TextStyle(fontSize: 12.5)),
        ),
        IconButton(
          icon: const Icon(Icons.copy_outlined, size: 18),
          tooltip: '复制',
          onPressed: () => _copy(value),
        ),
      ],
    );
  }

  /// 高德原生 SDK Key 卡：Android / iOS 两个字段，与 Web Key 分开申请。
  /// 运行时由 AmapMapView 在构建时读取（同意隐私后），不硬编码进包。
  Widget _amapSdkCard() {
    final filled =
        _settings.hasAmapSdkAndroidKey || _settings.hasAmapSdkIosKey;
    Widget field(String label, TextEditingController controller) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
            labelText: label,
            hintText: '粘贴你申请的 SDK Key',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );
    }

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
                  child: Text('高德 SDK Key（底图）',
                      style: Theme.of(context).textTheme.titleSmall),
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
                Text(filled ? '已填写' : '未填写',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            field('Android Key', _sdkAndroidController),
            field('iOS Key', _sdkIosController),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: () async {
                  await _settings.setAmapSdkKeys(
                    androidKey: _sdkAndroidController.text,
                    iosKey: _sdkIosController.text,
                  );
                  _snack('高德 SDK Key 已保存（重启 App 并同意隐私后生效）');
                },
                child: const Text('保存'),
              ),
            ),
            _getKeyButton(KeyConsoleUrls.amap),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'SDK Key 与 Web Key 是两种 Key，需在高德控制台分别创建。'
                '未填或未同意隐私时底图使用示意地图。',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
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
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleSmall),
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
                Text(filled ? '已填写' : '未填写',
                    style: Theme.of(context).textTheme.bodySmall),
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
                FilledButton.tonal(
                  onPressed: onSave,
                  child: const Text('保存'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _testing.contains(id)
                      ? null
                      : (onTest ??
                          () => _testLocalFormat(id, controller.text)),
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
