// 时长 / 距离 / 到达时间的展示格式化工具。

/// 秒 → 「45 秒」「38 分钟」「1 小时 5 分钟」。
String formatDuration(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final totalMinutes = (seconds / 60).round();
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return '$minutes 分钟';
  if (minutes == 0) return '$hours 小时';
  return '$hours 小时 $minutes 分钟';
}

/// 米 → 「850 米」「12.4 km」。
String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} 米';
  final km = meters / 1000;
  final text = km >= 100 ? km.toStringAsFixed(0) : km.toStringAsFixed(1);
  return '$text km';
}

/// DateTime → 「18:42」。
String formatClock(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
