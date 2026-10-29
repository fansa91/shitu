import 'dart:async';

import 'package:flutter/material.dart';

import '../models/poi.dart';
import '../services/api_exception.dart';
import '../services/history_service.dart';
import '../services/map_data_services.dart';
import '../services/settings_service.dart';
import '../utils/format.dart';

/// 搜索页：输入联想（真实 Web API 或示例数据），点结果返回给主页。
/// 空输入且有历史时展示搜索历史；选中结果会记入历史。
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.settings,
    required this.services,
    required this.history,
  });

  final SettingsService settings;
  final MapDataServices services;
  final HistoryService history;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<Poi> _results = const [];
  String? _error;
  bool _loading = false;
  String _query = '';
  Timer? _debounce;
  int _requestSeq = 0;

  bool get _showHistory =>
      _query.trim().isEmpty && widget.history.searches.isNotEmpty;

  bool get _isSample =>
      widget.services.isSampleFor(widget.settings.provider);

  @override
  void initState() {
    super.initState();
    _onQueryChanged('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 打字：防抖 300ms 后走联想接口；联想失败静默回落整词搜索。
  void _onQueryChanged(String query) {
    _query = query;
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      _requestSeq++; // 作废在途请求
      if (widget.history.searches.isNotEmpty) {
        setState(() {
          _results = const [];
          _loading = false;
          _error = null;
        });
        return;
      }
      unawaited(_runSearch('', useTips: false));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_runSearch(query, useTips: true)),
    );
  }

  /// 提交（回车）：立即走整词搜索，并把首条结果记入历史。
  Future<void> _onSubmitted(String query) async {
    _debounce?.cancel();
    if (query.trim().isEmpty) return;
    await _runSearch(query, useTips: false);
    if (_results.isNotEmpty) {
      await widget.history.addSearch(_results.first, query);
    }
  }

  Future<void> _runSearch(String query, {required bool useTips}) async {
    final provider = widget.settings.provider;
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final service = widget.services.serviceFor(provider);
    try {
      List<Poi> results;
      if (useTips) {
        try {
          results = await service.inputTips(query, provider);
        } catch (_) {
          // 联想接口失败/无 Key → 静默回落整词搜索，不打断输入。
          results = await service.searchSuggestions(query, provider);
        }
      } else {
        results = await service.searchSuggestions(query, provider);
      }
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } on MapApiException catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _results = const [];
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _results = const [];
        _error = '搜索失败，请稍后重试';
        _loading = false;
      });
    }
  }

  Future<void> _pick(Poi poi) async {
    await widget.history.addSearch(poi, _query);
    if (mounted) Navigator.of(context).pop(poi);
  }

  Widget _historyList(ThemeData theme) {
    final searches = widget.history.searches;
    return ListView(
      children: [
        Row(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 0, 4),
              child: Text('搜索历史',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const Spacer(),
            TextButton(
              onPressed: () async {
                await widget.history.clearSearches();
                if (mounted) setState(() {});
              },
              child: const Text('清空'),
            ),
          ],
        ),
        for (final entry in searches)
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(entry.poi.name),
            subtitle: Text(entry.poi.address,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.of(context).pop(entry.poi),
          ),
      ],
    );
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
          onSubmitted: _onSubmitted,
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
            child: _showHistory
                ? _historyList(theme)
                : _results.isEmpty && !_loading && _error == null
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
                            onTap: () => _pick(poi),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
