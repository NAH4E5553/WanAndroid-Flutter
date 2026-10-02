import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/app/startup/startup_reveal_layer.dart';
import 'package:wanandroid_flutter/src/core/startup/startup_reveal_controller.dart';

void main() {
  testWidgets('early content-ready fade preserves the current glyph scale', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: StartupRevealLayer(child: Text('target')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    double scale() => tester
        .widget<ScaleTransition>(
          find.descendant(
            of: find.byType(AnimatedScale),
            matching: find.byType(ScaleTransition),
          ),
        )
        .scale
        .value;
    final double before = scale();
    expect(before, greaterThan(1));
    expect(
      before,
      lessThan(1.07),
      reason: 'Probe is inside the reveal, not its end.',
    );
    container.read(startupRevealControllerProvider).markContentReady();
    await tester.pump();
    await tester.pump();
    expect(
      scale(),
      closeTo(before, .001),
      reason:
          'A fast data response must not snap a partially scaled icon to 1.08.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
