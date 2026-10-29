import 'package:flutter/material.dart';

import '../models/poi.dart';
import '../services/map_data_service.dart';
import '../services/settings_service.dart';
import '../utils/format.dart';

/// 搜索页：输入联想（骨架阶段为示例数据），点结果返回给主页。
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.settings,
    required this.mapData,
  });

  final SettingsService settings;
  final MapDataService mapData;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<Poi> _results = SampleMapDataService.samplePois;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onQueryChanged(String query) async {
    final results = await widget.mapData
        .searchSuggestions(query, widget.settings.provider);
    if (mounted) setState(() => _results = results);
  }

  IconData _iconFor(Poi poi) {
    if (poi.category.contains('交通')) return Icons.train_outlined;
    if (poi.category.contains('购物')) return Icons.local_mall_outlined;
    if (poi.category.contains('公园')) return Icons.park_outlined;
    return Icons.place_outlined;
  }

  @override
  Widget build(BuildContext context) {
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
      body: ListView.separated(
        itemCount: _results.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final poi = _results[index];
          return ListTile(
            leading: Icon(_iconFor(poi)),
            title: Text(poi.name),
            subtitle:
                Text('${poi.address} · ${formatDistance(poi.distanceMeters)}'),
            trailing: Text(
              widget.settings.provider.displayName.replaceAll('地图', ''),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            onTap: () => Navigator.of(context).pop(poi),
          );
        },
      ),
    );
  }
}
