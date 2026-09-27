import 'package:flutter/material.dart';

/// WanAndroid 基线人物描边图标（`ic_person` 矢量转换）。
/// viewport 24、描边宽 2、圆头圆角连接、无填充；颜色由调用方按主题角色传入。
class WanPersonIcon extends StatelessWidget {
  const WanPersonIcon({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: WanPersonPainter(color));
}

class WanPersonPainter extends CustomPainter {
  const WanPersonPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24);
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(const Offset(12, 8), 4, paint);
    final Path body = Path()
      ..moveTo(4, 21)
      ..cubicTo(4, 16.6, 7.6, 14, 12, 14)
      ..cubicTo(16.4, 14, 20, 16.6, 20, 21);
    canvas.drawPath(body, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant WanPersonPainter oldDelegate) =>
      oldDelegate.color != color;
}
