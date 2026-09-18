import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wanandroid_flutter/src/app/router/branch_restoration_controller.dart';
import 'package:wanandroid_flutter/src/core/ui/app_scaffold.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) => AppScaffold(
    body: navigationShell,
    bottomBar: NavigationBar(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: (int index) {
        BranchRestorationScope.of(context).selectBranch(index);
        navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        );
      },
      destinations: const <NavigationDestination>[
        NavigationDestination(icon: _TabIcon(index: 0), label: '首页'),
        NavigationDestination(icon: _TabIcon(index: 1), label: '专题'),
        NavigationDestination(icon: _TabIcon(index: 2), label: '我的'),
      ],
    ),
  );
}

class _TabIcon extends StatelessWidget {
  const _TabIcon({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(24),
    painter: _TabIconPainter(index: index, color: IconTheme.of(context).color!),
  );
}

class _TabIconPainter extends CustomPainter {
  const _TabIconPainter({required this.index, required this.color});

  final int index;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double unit = size.width / 24;
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * unit;
    switch (index) {
      case 0:
        final Path roof = Path()
          ..moveTo(3 * unit, 11 * unit)
          ..lineTo(12 * unit, 3 * unit)
          ..lineTo(21 * unit, 11 * unit);
        canvas.drawPath(roof, paint);
        canvas.drawRect(
          Rect.fromLTWH(6 * unit, 11 * unit, 12 * unit, 10 * unit),
          paint,
        );
        break;
      case 1:
        for (final double x in <double>[3, 14]) {
          for (final double y in <double>[3, 14]) {
            canvas.drawRect(
              Rect.fromLTWH(x * unit, y * unit, 7 * unit, 7 * unit),
              paint,
            );
          }
        }
        break;
      case 2:
        canvas.drawCircle(Offset(12 * unit, 7 * unit), 4 * unit, paint);
        canvas.drawArc(
          Rect.fromLTWH(4 * unit, 14 * unit, 16 * unit, 12 * unit),
          3.141592653589793,
          3.141592653589793,
          false,
          paint,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _TabIconPainter oldDelegate) =>
      index != oldDelegate.index || color != oldDelegate.color;
}
