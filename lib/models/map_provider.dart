/// 地图数据服务商（搜索 / 算路的数据源）。
///
/// 底图统一用高德 Web 瓦片（不需要 Key）；三家仅作为可切换的
/// 搜索与算路数据源（走 Web API）。
enum MapProvider {
  amap('高德地图', '高德 Web Key'),
  baidu('百度地图', '百度 Web AK'),
  tencent('腾讯地图', '腾讯 Web Key');

  const MapProvider(this.displayName, this.keyLabel);

  /// 中文名，如「高德地图」。
  final String displayName;

  /// 该服务商 Key 在设置页的字段名。
  final String keyLabel;
}

/// 语音播报引擎。
enum TtsEngine {
  system('系统语音'),
  nvidia('英伟达 TTS');

  const TtsEngine(this.displayName);

  final String displayName;
}

/// 出行方式。
enum TransportMode {
  driving('驾车'),
  transit('公交'),
  walking('步行'),
  cycling('骑行');

  const TransportMode(this.displayName);

  final String displayName;
}
