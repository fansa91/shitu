import 'package:flutter/material.dart';

import '../models/map_provider.dart';
import '../models/route_plan.dart';
import '../services/settings_service.dart';
import '../utils/format.dart';
import '../widgets/fake_map.dart';

/// 导航页：深色沉浸式。顶部指引横幅、拥堵提示条、速度气泡、底部信息条。
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({
    super.key,
    required this.option,
    required this.destinationName,
    required this.settings,
    this.simulated = false,
  });

  final RouteOption option;
  final String destinationName;
  final SettingsService settings;
  final bool simulated;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  bool _showCongestionAlert = true;

  String get _voiceLabel => widget.settings.ttsEngine == TtsEngine.nvidia
      ? '语音 · 英伟达'
      : '语音 · 系统';

  Future<void> _exit() async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('到达小结'),
        content: Text(
          '目的地：${widget.destinationName}\n'
          '里程：${formatDistance(widget.option.distanceMeters)}\n'
          '时长：${formatDuration(widget.option.durationSeconds)}'
          '${widget.simulated ? '\n（本次为模拟导航）' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('保存轨迹'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('share'),
            child: const Text('分享'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('close'),
            child: const Text('完成'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'save' || action == 'share') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(action == 'save' ? '轨迹已保存（骨架占位）' : '分享功能骨架占位')),
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final eta = DateTime.now()
        .add(Duration(seconds: widget.option.durationSeconds));
    return Scaffold(
      backgroundColor: const Color(0xFF101826),
      body: Stack(
        children: [
          const Positioned.fill(child: FakeMap(dark: true, showRoute: true)),
          // 顶部指引横幅
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0D5C46),
                  borderRadius: BorderRadius.circular(18),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const Icon(Icons.turn_right,
                        color: Colors.white, size: 44),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '300 米',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.simulated ? '模拟：右转 进入深南大道' : '右转 进入深南大道',
                          style: const TextStyle(
                              color: Color(0xFFC9ECDF), fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 拥堵重规划提示条
          if (_showCongestionAlert)
            Positioned(
              left: 12,
              right: 12,
              top: 128,
              child: Material(
                color: const Color(0xFFFDF3D7),
                borderRadius: BorderRadius.circular(13),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      const Text(
                        '前方 2 km 拥堵，已重新规划',
                        style: TextStyle(fontSize: 12.5, color: Color(0xFF7A5B00)),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () =>
                            setState(() => _showCongestionAlert = false),
                        child: const Text('接受'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: '忽略',
                        onPressed: () =>
                            setState(() => _showCongestionAlert = false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // 速度 / 限速气泡
          Positioned(
            left: 14,
            top: 250,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE8453C), width: 3),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('65',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF17233B),
                          height: 1)),
                  SizedBox(height: 2),
                  Text('限速 60',
                      style: TextStyle(fontSize: 9.5, color: Colors.grey)),
                ],
              ),
            ),
          ),
          // 底部信息条
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: const Color(0xFF101826),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '剩余 ${formatDuration(widget.option.durationSeconds)} · '
                      '${formatDistance(widget.option.distanceMeters)} · '
                      '预计 ${formatClock(eta)} 到达 · 深南大道',
                      style: const TextStyle(
                          color: Color(0xFFDBE6F2), fontSize: 13.5),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _navButton('总览', () {}),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _navButton(_voiceLabel, () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      '当前播报引擎：$_voiceLabel（骨架占位）')),
                            );
                          }),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _navButton('退出导航', _exit,
                              background: const Color(0xFF5C2320),
                              foreground: const Color(0xFFFFB4AB)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navButton(String label, VoidCallback onTap,
      {Color background = const Color(0xFF1F2C3F),
      Color foreground = const Color(0xFFDBE6F2)}) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        padding: const EdgeInsets.symmetric(vertical: 11),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 12.5)),
    );
  }
}
