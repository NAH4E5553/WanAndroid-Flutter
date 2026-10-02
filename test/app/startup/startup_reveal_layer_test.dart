import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/app/startup/startup_reveal_layer.dart';
import 'package:wanandroid_flutter/src/core/startup/startup_reveal_controller.dart';

void main() {
  testWidgets('occluding layer blocks hits and semantics of the content', (
    tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    var taps = 0;
    try {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: StartupRevealLayer(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps += 1,
                child: const Text('app'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('app'), warnIfMissed: false);
      await tester.pump();
      // The overlay is up with a semantics-blocking barrier over the content.
      expect(
        find.byKey(const ValueKey<String>('startup-overlay')),
        findsOneWidget,
      );
      expect(find.byType(BlockSemantics), findsWidgets);
      expect(
        find.bySemanticsLabel('app'),
        findsNothing,
        reason: 'occluded content must be invisible to semantics',
      );
    } finally {
      semantics.dispose();
    }
    expect(taps, 0, reason: 'occluded content must not receive taps');
    expect(
      refPhase(tester),
      isNot(StartupRevealPhase.done),
      reason: 'the layer must still be up during reveal',
    );
  });

  testWidgets('first frame starts the reveal, then exit completes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: StartupRevealLayer(child: Text('app'))),
      ),
    );
    await tester.pump(); // post-frame callback marks the first frame.
    expect(refPhase(tester), StartupRevealPhase.revealing);
    // The reveal ends when the scale animation completes: its onEnd fires on
    // the completing frame, and the controller notification lands right after.
    // The frame loop re-arms once per pump: each dwell check lands on the
    // pump's trailing rebuild frame, so allow one extra pump per transition.
    // Timer-driven reveal completion fires when this pump's virtual clock
    // reaches 480ms; the fade then plays out over its own 220ms budget.
    await tester.pump(const Duration(milliseconds: 480));
    expect(refPhase(tester), StartupRevealPhase.exiting);
    await tester.pump(const Duration(milliseconds: 220));
    expect(refPhase(tester), StartupRevealPhase.done);
    // 退出后不会因再次 pump 重新遮挡（幂等 done）。
    await tester.pump(const Duration(seconds: 2));
    expect(refPhase(tester), StartupRevealPhase.done);
  });

  testWidgets('content becomes hittable and readable after done', (
    tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    var taps = 0;
    try {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: StartupRevealLayer(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps += 1,
                child: const Text('app'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(); // deferred removal frame
      await tester.pump(const Duration(milliseconds: 500));
      // Terminal state: the overlay (and with it the semantics-blocking
      // BlockSemantics) is gone, so the content is fully interactive again.
      // (The Navigator keeps its own BlockSemantics; ours is gone with the
      // overlay, which is what gates the content.)
      expect(
        find.byKey(const ValueKey<String>('startup-overlay')),
        findsNothing,
      );
    } finally {
      semantics.dispose();
    }
    expect(refPhase(tester), StartupRevealPhase.done);
    await tester.pump(); // overlay removal lands on the frame after done.
    await tester.tap(find.text('app'));
    expect(taps, 1);
  });

  testWidgets('backgrounding during the reveal collapses without replay', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: StartupRevealLayer(child: Text('app'))),
      ),
    );
    await tester.pump();
    expect(refPhase(tester), StartupRevealPhase.revealing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(refPhase(tester), StartupRevealPhase.done);
    // 返回前台（resumed）也不重播。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    expect(refPhase(tester), StartupRevealPhase.done);
  });

  testWidgets('reduce motion skips the reveal with a brief exit', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const StartupRevealLayer(child: Text('app')),
          ),
        ),
      ),
    );
    await tester.pump(); // first frame with reduce-motion: enter brief exit.
    expect(refPhase(tester), StartupRevealPhase.exiting);
    // The 700ms reveal+exit watchdog converges the layer; the overlay removal
    // paints on the frame right after it fires.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(refPhase(tester), StartupRevealPhase.done);
    expect(find.byKey(const ValueKey<String>('startup-overlay')), findsNothing);
    expect(find.bySemanticsLabel('app'), findsOneWidget);
  });

  testWidgets('Android dark background follows the dark resource', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: StartupRevealLayer(child: Text('app'))),
        ),
      );
      // Before the first post-frame callback the layer is still occluding and
      // the overlay paints the native dark background.
      expect(overlayColor(tester), const Color(0xFF000000));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iOS start screen stays white in dark mode (static storyboard)', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: StartupRevealLayer(child: Text('app'))),
        ),
      );
      // pumpWidget has not run a post-frame callback yet: the layer is
      // mounted and occluding, so the overlay mirrors the static white
      // storyboard.
      expect(overlayColor(tester), const Color(0xFFFFFFFF));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Color overlayColor(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find.byKey(const ValueKey<String>('startup-splash-background')),
    )
    .color;

StartupRevealPhase refPhase(WidgetTester tester) {
  final BuildContext context = tester.element(find.text('app'));
  return ProviderScope.containerOf(context).read(startupRevealPhaseProvider);
}
