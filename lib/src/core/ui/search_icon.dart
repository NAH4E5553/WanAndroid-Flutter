import 'package:flutter/material.dart';

class AppSearchIcon extends StatelessWidget {
  const AppSearchIcon({this.size = 20, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _SearchPainter(Theme.of(context).colorScheme.onSurfaceVariant),
  );
}

class _SearchPainter extends CustomPainter {
  const _SearchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(
      Offset(size.width * 0.43, size.height * 0.43),
      size.width * 0.28,
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.64, size.height * 0.64),
      Offset(size.width * 0.86, size.height * 0.86),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SearchPainter oldDelegate) =>
      color != oldDelegate.color;
}
