import 'package:flutter/material.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({required this.title, required this.onBack, super.key});

  final String title;
  final VoidCallback onBack;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) => AppBar(
    toolbarHeight: 64,
    leading: IconButton(
      tooltip: '返回',
      onPressed: onBack,
      icon: CustomPaint(
        size: const Size.square(24),
        painter: _BackPainter(Theme.of(context).colorScheme.onSurface),
      ),
    ),
    title: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    backgroundColor: Theme.of(context).colorScheme.surface,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    titleSpacing: 0,
  );
}

class _BackPainter extends CustomPainter {
  const _BackPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Path path = Path()
      ..moveTo(size.width * 0.67, size.height * 0.2)
      ..lineTo(size.width * 0.34, size.height * 0.5)
      ..lineTo(size.width * 0.67, size.height * 0.8);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BackPainter oldDelegate) =>
      color != oldDelegate.color;
}
