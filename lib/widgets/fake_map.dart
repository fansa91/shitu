import 'package:flutter/material.dart';

/// 骨架阶段的假地图：用 CustomPainter 画风格化路网占位，
/// 正式版替换为高德原生地图 Widget（接口保持：深色变体、路线、标记）。
class FakeMap extends StatelessWidget {
  const FakeMap({
    super.key,
    this.dark = false,
    this.showRoute = false,
    this.showDestinationPin = false,
    this.showLocationDot = true,
  });

  /// 深色变体（导航页）。
  final bool dark;

  /// 是否画双路线（选中蓝粗线 + 备选灰线）与起终点标记。
  final bool showRoute;

  /// 是否画目的地红色图钉（POI 详情态）。
  final bool showDestinationPin;

  final bool showLocationDot;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FakeMapPainter(
        dark: dark,
        showRoute: showRoute,
        showDestinationPin: showDestinationPin,
        showLocationDot: showLocationDot,
      ),
      size: Size.infinite,
    );
  }
}

class _FakeMapPainter extends CustomPainter {
  _FakeMapPainter({
    required this.dark,
    required this.showRoute,
    required this.showDestinationPin,
    required this.showLocationDot,
  });

  final bool dark;
  final bool showRoute;
  final bool showDestinationPin;
  final bool showLocationDot;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 底图
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = dark ? const Color(0xFF141C29) : const Color(0xFFE9EFE4),
    );

    // 绿地
    final parkPaint = Paint()
      ..color = dark ? const Color(0xFF1B2A22) : const Color(0xFFCFE5C0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.05, h * 0.52, w * 0.3, h * 0.13),
        const Radius.circular(10),
      ),
      parkPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.66, h * 0.16, w * 0.28, h * 0.11),
        const Radius.circular(10),
      ),
      parkPaint,
    );

    // 河流
    final river = Path()
      ..moveTo(0, h * 0.76)
      ..quadraticBezierTo(w * 0.35, h * 0.68, w * 0.55, h * 0.8)
      ..quadraticBezierTo(w * 0.75, h * 0.9, w, h * 0.84)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      river,
      Paint()..color = dark ? const Color(0xFF1D3552) : const Color(0xFFBCD9F5),
    );

    // 路网：横竖网格 + 主干道
    final minorRoad = Paint()
      ..color = dark ? const Color(0xFF26334A) : Colors.white
      ..strokeWidth = dark ? 7 : 9;
    final majorRoad = Paint()
      ..color = dark ? const Color(0xFF31435F) : const Color(0xFFF6D98A)
      ..strokeWidth = 5;
    for (final fx in [0.12, 0.3, 0.52, 0.74, 0.9]) {
      canvas.drawLine(Offset(w * fx, 0), Offset(w * fx, h), minorRoad);
    }
    for (final fy in [0.14, 0.3, 0.5, 0.66]) {
      canvas.drawLine(Offset(0, h * fy), Offset(w, h * fy), minorRoad);
    }
    canvas.drawLine(Offset(0, h * 0.5), Offset(w, h * 0.5), majorRoad);
    canvas.drawLine(Offset(w * 0.52, 0), Offset(w * 0.52, h), majorRoad);

    if (showRoute) {
      final start = Offset(w * 0.16, h * 0.72);
      final end = Offset(w * 0.82, h * 0.3);
      // 备选路线（灰）
      final alt = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(w * 0.2, h * 0.45, w * 0.48, h * 0.44)
        ..quadraticBezierTo(w * 0.72, h * 0.44, end.dx, end.dy);
      canvas.drawPath(
        alt,
        Paint()
          ..color = const Color(0xFFB9C2CC)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
      // 选中路线（蓝粗线）
      final main = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(w * 0.34, h * 0.66, w * 0.44, h * 0.5)
        ..quadraticBezierTo(w * 0.52, h * 0.36, end.dx, end.dy);
      canvas.drawPath(
        main,
        Paint()
          ..color = const Color(0xFF1A73E8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round,
      );
      _drawDot(canvas, start, const Color(0xFF34A853));
      _drawPin(canvas, end);
    } else if (showDestinationPin) {
      _drawPin(canvas, Offset(w * 0.5, h * 0.36));
    }

    if (showLocationDot) {
      final center = Offset(w * 0.44, h * 0.56);
      canvas.drawCircle(
        center,
        17,
        Paint()..color = const Color(0xFF1A73E8).withValues(alpha: 0.2),
      );
      canvas.drawCircle(center, 8, Paint()..color = const Color(0xFF1A73E8));
      canvas.drawCircle(
        center,
        8,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  void _drawDot(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(center, 8, Paint()..color = color);
    canvas.drawCircle(
      center,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  void _drawPin(Canvas canvas, Offset tip) {
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(tip.dx - 13, tip.dy - 16, tip.dx - 11, tip.dy - 26)
      ..quadraticBezierTo(tip.dx - 8, tip.dy - 38, tip.dx, tip.dy - 38)
      ..quadraticBezierTo(tip.dx + 8, tip.dy - 38, tip.dx + 11, tip.dy - 26)
      ..quadraticBezierTo(tip.dx + 13, tip.dy - 16, tip.dx, tip.dy);
    canvas.drawPath(path, Paint()..color = const Color(0xFFE8453C));
    canvas.drawCircle(
      Offset(tip.dx, tip.dy - 26),
      4.5,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_FakeMapPainter oldDelegate) =>
      dark != oldDelegate.dark ||
      showRoute != oldDelegate.showRoute ||
      showDestinationPin != oldDelegate.showDestinationPin ||
      showLocationDot != oldDelegate.showLocationDot;
}
