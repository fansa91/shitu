import 'package:flutter/material.dart';

import '../models/poi.dart';
import '../services/api_exception.dart';
import '../services/map_data_services.dart';
import '../services/settings_service.dart';
import '../utils/format.dart';

/// 搜索页：输入联想（真实 Web API 或示例数据），点结果返回给主页。
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.settings,
    required this.services,
  });

  final SettingsService settings;
  final MapDataServices services;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<Poi> _results = const [];
  String? _error;
  bool _loading = false;

  bool get _isSample =>
      widget.services.isSampleFor(widget.settings.provider);

  @override
  void initState() {
    super.initState();
    _onQueryChanged('');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onQueryChanged(String query) async {
    final provider = widget.settings.provider;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.services
          .serviceFor(provider)
          .searchSuggestions(query, provider);
      if (mounted) {
        setState(() {
          _results = results;
          _loading = false;
        });
      }
    } on MapApiException catch (e) {
      if (mounted) {
        setState(() {
          _results = const [];
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _results = const [];
          _error = '搜索失败，请稍后重试';
          _loading = false;
        });
      }
    }
  }

  IconData _iconFor(Poi poi) {
    if (poi.category.contains('交通')) return Icons.train_outlined;
    if (poi.category.contains('购物')) return Icons.local_mall_outlined;
    if (poi.category.contains('公园')) return Icons.park_outlined;
    return Icons.place_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '搜索地点 / 地址',
            border: InputBorder.none,
          ),
          onChanged: _onQueryChanged,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isSample)
            Container(
              width: double.infinity,
              color: theme.colorScheme.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '示例数据：未填 ${widget.settings.provider.keyLabel}，'
                '当前结果为内置示例，去设置填写后即切换真实搜索',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (_error != null)
            Container(
              width: double.infinity,
              color: theme.colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(_error!, style: theme.textTheme.bodySmall),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _results.isEmpty && !_loading && _error == null
                ? const Center(child: Text('没有结果，换个关键词试试'))
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final poi = _results[index];
                      return ListTile(
                        leading: Icon(_iconFor(poi)),
                        title: Text(poi.name),
                        subtitle: Text(poi.distanceMeters == null
                            ? poi.address
                            : '${poi.address} · '
                                '${formatDistance(poi.distanceMeters!)}'),
                        trailing: Text(
                          widget.settings.provider.displayName
                              .replaceAll('地图', ''),
                          style: theme.textTheme.bodySmall,
                        ),
                        onTap: () => Navigator.of(context).pop(poi),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
