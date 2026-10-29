import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/map_provider.dart';
import '../services/settings_service.dart';

/// 设置页：数据源单选、Key 管理（用户自填）、申请指南、语音、关于。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings});

  final SettingsService settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// 申请指南里的占位 SHA1，发布前替换为真实发布签名指纹。
  static const _placeholderSha1 = 'AA:BB:CC:…（占位，发布前替换）';
  static const _packageName = 'com.shitu.app';

  final Map<MapProvider, TextEditingController> _keyControllers = {};
  final _nvidiaController = TextEditingController();
  final Map<String, String> _testResults = {};

  SettingsService get _settings => widget.settings;

  @override
  void initState() {
    super.initState();
    for (final p in MapProvider.values) {
      _keyControllers[p] =
          TextEditingController(text: _settings.keyFor(p));
    }
    _nvidiaController.text = _settings.nvidiaKey;
  }

  @override
  void dispose() {
    for (final c in _keyControllers.values) {
      c.dispose();
    }
    _nvidiaController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 骨架阶段「测试连接」：仅做本地格式校验，不发起真实 API 请求。
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
              _sectionTitle('API Key 管理（用户自填）'),
              for (final p in MapProvider.values)
                _keyCard(
                  id: p.name,
                  title: p.keyLabel,
                  controller: _keyControllers[p]!,
                  filled: _settings.hasKeyFor(p),
                  onSave: () async {
                    await _settings.setKeyFor(p, _keyControllers[p]!.text);
                    _snack('${p.keyLabel} 已保存（改 Key 后需重启 App 生效）');
                  },
                ),
              _keyCard(
                id: 'nvidia',
                title: '英伟达 TTS Key（可选）',
                controller: _nvidiaController,
                filled: _settings.nvidiaKey.isNotEmpty,
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
                    _copyRow('发布 SHA1（占位）', _placeholderSha1),
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
              const Card(
                child: ListTile(
                  title: Text('识途'),
                  subtitle: Text('版本跟随构建版本（由 tag / CI 注入，不硬编码）'),
                ),
              ),
            ],
          ),
        );
      },
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

  Widget _keyCard({
    required String id,
    required String title,
    required TextEditingController controller,
    required bool filled,
    required VoidCallback onSave,
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
                  onPressed: () => _testLocalFormat(id, controller.text),
                  child: const Text('测试连接'),
                ),
              ],
            ),
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
