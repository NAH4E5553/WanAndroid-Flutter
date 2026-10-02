import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/app/startup/startup_reveal_layer.dart';
import 'package:wanandroid_flutter/src/core/startup/startup_reveal_controller.dart';

void main() {
  final LiveTestWidgetsFlutterBinding binding =
      LiveTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('reduced motion exits with framework frames only', (
    tester,
  ) async {
    final ProviderContainer container = ProviderContainer();
    try {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: StartupRevealLayer(child: Text('target')),
            ),
          ),
        ),
      );
      // No pump, gesture, network, or other ticker supplies an extra frame.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(container.read(startupRevealControllerProvider).isDone, isTrue);
      expect(
        find.byKey(const ValueKey<String>('startup-overlay')),
        findsNothing,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }
  });
}
