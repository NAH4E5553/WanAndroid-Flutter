import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/startup/startup_reveal_controller.dart';

// Frame-driven contract: the controller holds no timers. Phase dwell times
// are owned by the layer's animations, which report back through
// markRevealAnimationDone / markExitFinished; the watchdog concept is covered
// by the fact that every transition notifies listeners and the layer
// rebuilds through a ListenableBuilder (a painted frame per handoff).
void main() {
  test('reveal chain advances through explicit animation completion calls', () {
    final StartupRevealController controller = StartupRevealController();
    final List<StartupRevealPhase> phases = <StartupRevealPhase>[];
    controller.addListener(() => phases.add(controller.phase));

    expect(controller.phase, StartupRevealPhase.occluding);
    controller.markFirstFrame();
    expect(controller.phase, StartupRevealPhase.revealing);
    controller.markRevealAnimationDone();
    expect(controller.phase, StartupRevealPhase.exiting);
    controller.markExitFinished();
    expect(controller.phase, StartupRevealPhase.done);
    expect(controller.isDone, isTrue);
    expect(phases, <StartupRevealPhase>[
      StartupRevealPhase.revealing,
      StartupRevealPhase.exiting,
      StartupRevealPhase.done,
    ]);
    controller.dispose();
  });

  test('terminal state is absorbing: late callbacks are idempotent no-ops', () {
    final StartupRevealController controller = StartupRevealController();
    controller.markFirstFrame();
    controller.markContentReady(); // early exit
    expect(controller.phase, StartupRevealPhase.exiting);
    controller.markExitFinished();
    expect(controller.phase, StartupRevealPhase.done);

    var notifications = 0;
    controller.addListener(() => notifications += 1);
    final int generation = controller.generation;
    controller
      ..markFirstFrame()
      ..markRevealAnimationDone()
      ..markContentReady()
      ..markExitFinished()
      ..handleBackgrounded();
    expect(controller.phase, StartupRevealPhase.done);
    expect(controller.generation, generation);
    expect(notifications, 0);
    controller.dispose();
  });

  test('reduce motion skips the reveal and goes straight to exit', () {
    final StartupRevealController controller = StartupRevealController();
    controller.markFirstFrame(reduceMotion: true);
    expect(controller.phase, StartupRevealPhase.exiting);
    controller.markExitFinished();
    expect(controller.phase, StartupRevealPhase.done);
    controller.dispose();
  });

  test('content-ready ends the reveal early from any pre-exit phase', () {
    final StartupRevealController controller = StartupRevealController();
    controller.markFirstFrame();
    controller.markContentReady();
    expect(controller.phase, StartupRevealPhase.exiting);
    controller.dispose();

    // Even directly from occluding (content ready before the first frame
    // callback arrives).
    final StartupRevealController other = StartupRevealController();
    other.markContentReady();
    expect(other.phase, StartupRevealPhase.exiting);
    other.dispose();
  });

  test('backgrounding collapses from any live phase without replay', () {
    for (final StartupRevealPhase start in <StartupRevealPhase>[
      StartupRevealPhase.occluding,
      StartupRevealPhase.revealing,
      StartupRevealPhase.exiting,
    ]) {
      final StartupRevealController controller = StartupRevealController();
      if (start == StartupRevealPhase.revealing) {
        controller.markFirstFrame();
      } else if (start == StartupRevealPhase.exiting) {
        controller
          ..markFirstFrame()
          ..markContentReady();
      }
      expect(controller.phase, start);
      controller.handleBackgrounded();
      expect(controller.phase, StartupRevealPhase.done);
      controller.markFirstFrame();
      expect(controller.phase, StartupRevealPhase.done);
      controller.dispose();
    }
  });

  test('dispose is safe from any phase and stops further transitions', () {
    for (final StartupRevealPhase start in <StartupRevealPhase>[
      StartupRevealPhase.occluding,
      StartupRevealPhase.exiting,
    ]) {
      final StartupRevealController controller = StartupRevealController();
      if (start == StartupRevealPhase.exiting) {
        controller
          ..markFirstFrame()
          ..markContentReady();
      }
      var notifications = 0;
      controller.addListener(() => notifications += 1);
      controller.dispose();
      controller.markFirstFrame();
      controller.markExitFinished();
      expect(notifications, 0);
    }
  });
}
