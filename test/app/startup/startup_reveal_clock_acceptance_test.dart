import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/app/startup/startup_reveal_layer.dart';
import 'package:wanandroid_flutter/src/core/startup/startup_reveal_controller.dart';

void main() {
  testWidgets('wall-clock frame report cannot finish a 100ms reveal', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = ProviderContainer();
    try {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MediaQuery(
            data: MediaQueryData(),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: StartupRevealLayer(child: Text('pending target')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final StartupRevealController controller = container.read(
        startupRevealControllerProvider,
      );
      expect(controller.phase, StartupRevealPhase.revealing);
      final double scale = tester
          .widget<ScaleTransition>(find.byType(ScaleTransition))
          .scale
          .value;
      expect(scale, inExclusiveRange(1.0, 1.07));

      // Deliver through the framework's production callback, not the private
      // layer method. Engine wall time and scheduler animation time use
      // different epochs. No target-ready signal is sent in this test.
      const int wallEpoch = 1790899200000000;
      final TimingsCallback? report = tester.platformDispatcher.onReportTimings;
      expect(report, isNotNull);
      report!(<FrameTiming>[
        FrameTiming(
          vsyncStart: 100000,
          buildStart: 100001,
          buildFinish: 101000,
          rasterStart: 101001,
          rasterFinish: 102000,
          rasterFinishWallTime: wallEpoch + 102000,
        ),
      ]);
      expect(
        controller.phase,
        StartupRevealPhase.revealing,
        reason:
            'A first engine report at 100ms is not 480ms of reveal playback.',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.phase, StartupRevealPhase.exiting);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }
  });
}
