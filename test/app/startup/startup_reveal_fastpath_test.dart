import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/app/startup/startup_reveal_layer.dart';
import 'package:wanandroid_flutter/src/core/diagnostics/startup_metrics.dart';
import 'package:wanandroid_flutter/src/core/startup/startup_reveal_controller.dart';

/// Developer-side regressions for the R03/R10 rework: the reduce-motion exit
/// keeps one genuinely unoccluded frame before terminal, and a fast-ready
/// content signal ends the reveal early instead of playing the full teaser.
void main() {
  testWidgets('reduce motion keeps one unoccluded exit frame', (tester) async {
    final StartupMetrics previous = StartupMetrics.instance;
    int clock = 100;
    final List<Map<String, Object>> events = <Map<String, Object>>[];
    StartupMetrics.instance = StartupMetrics(
      enabled: true,
      clock: () => clock,
      emit: events.add,
    )..start();
    addTearDown(() => StartupMetrics.instance = previous);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: StartupRevealLayer(child: Text('app')),
          ),
        ),
      ),
    );
    // First frame: the opaque layer is still painted (reduce-motion moves the
    // controller to exiting in its post-frame callback, not retroactively).
    expect(
      find.byKey(const ValueKey<String>('startup-splash-background')),
      findsOneWidget,
    );
    clock = 200;
    StartupMetrics.instance.recordTimings(<FrameTiming>[
      FrameTiming(
        vsyncStart: 99,
        buildStart: 100,
        buildFinish: 110,
        rasterStart: 111,
        rasterFinish: 130,
        rasterFinishWallTime: 130,
      ),
    ]);
    expect(
      events.where((e) => e['point'] == 'startup_layer_exit'),
      isEmpty,
      reason: 'the occluded first raster must not count as the layer exit',
    );

    // After the brief exit the layer is gone: a rendered frame from now on
    // genuinely shows the content and completes the exit point.
    // Reduce-motion still runs the short fade: let the 220ms exit complete
    // (its onEnd marks done) and rebuild without the overlay.
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey<String>('startup-splash-background')),
      findsNothing,
    );
    // The done rebuild reported the exit at clock=200 (build time); its
    // raster completes at 230 (clock advanced so mark() accepts it).
    clock = 230;
    StartupMetrics.instance.recordTimings(<FrameTiming>[
      FrameTiming(
        vsyncStart: 199,
        buildStart: 200,
        buildFinish: 210,
        rasterStart: 211,
        rasterFinish: 230,
        rasterFinishWallTime: 230,
      ),
    ]);
    expect(
      events.where((e) => e['point'] == 'startup_layer_exit'),
      hasLength(1),
    );
  });

  testWidgets(
    'content-ready ends the reveal early without waiting the full teaser',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: StartupRevealLayer(child: Text('app'))),
        ),
      );
      await tester.pump(); // first frame → revealing
      final StartupRevealController controller = ProviderScope.containerOf(
        tester.element(find.text('app')),
      ).read(startupRevealControllerProvider);
      expect(controller.phase, StartupRevealPhase.revealing);
      // Content reports ready after 100ms (well before the 480ms teaser ends).
      await tester.pump(const Duration(milliseconds: 100));
      controller.markContentReady();
      expect(controller.phase, StartupRevealPhase.exiting);
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.phase, StartupRevealPhase.done);
      // Total: ~320ms < 480+220ms full path.
    },
  );
}
