import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Phases of the unified startup reveal, in display order.
enum StartupRevealPhase {
  /// Static composition identical to the native launch screen.
  occluding,

  /// The lightweight in-app animation is running on the static match.
  revealing,

  /// The startup layer is fading out and handing rendering to the app.
  exiting,

  /// The startup layer is removed for the rest of the process lifetime.
  done,
}

/// Single source of truth for whether the startup layer still covers content.
///
/// FRAME-DRIVEN: the controller holds NO timers. Phase dwell times are owned
/// by the layer's animations (scale for the reveal, fade for the exit), which
/// report completion back through [markRevealAnimationDone] and
/// [markExitFinished]. Every transition notifies listeners, and the layer
/// rebuilds through a ListenableBuilder — so each handoff step schedules and
/// paints its own real frame, without depending on timer scheduling that can
/// stall in reduced-animation or frozen-frame environments.
class StartupRevealController extends ChangeNotifier {
  StartupRevealController({
    this.revealDuration = const Duration(milliseconds: 480),
    this.exitDuration = const Duration(milliseconds: 220),
    this.maxOcclusion = const Duration(seconds: 5),
  });

  final Duration revealDuration;
  final Duration exitDuration;

  /// Process-wide instance registered by the startup layer. Feature code
  /// reads it through [coveredNow] without importing app modules; a null
  /// instance means no overlay exists anywhere.
  static StartupRevealController? instance;

  /// Whether any startup overlay currently covers the screen.
  static bool get coveredNow => !(instance?.isDone ?? true);

  /// Invoked when the layer reaches its terminal phase. Set by the home
  /// ViewModel to republish its snapshot on the removal frame; never persists
  /// across hosts.
  static void Function()? onDone;

  /// Kept as a documented budget: the layer's own animations always reach
  /// done (reveal 480ms + exit 220ms; reduce-motion 32ms) because each
  /// transition schedules a real frame. There is deliberately no timer to
  /// enforce it — a frozen engine cannot paint anything anyway, so the user
  /// is still on the native launch screen rather than behind a stuck overlay.
  final Duration maxOcclusion;

  StartupRevealPhase _phase = StartupRevealPhase.occluding;
  int _generation = 0;
  bool _disposed = false;

  StartupRevealPhase get phase => _phase;

  /// Monotonic counter; callbacks capture it and drop stale applications.
  int get generation => _generation;

  bool get isDone => _phase == StartupRevealPhase.done;

  /// Called once the first frame that mirrors the native screen exists.
  /// Idempotent: theme rebuilds and duplicate callbacks are no-ops. With the
  /// reduce-motion accessibility setting the reveal is skipped and the layer
  /// goes straight into its short exit.
  void markFirstFrame({bool reduceMotion = false}) {
    if (_disposed || _phase != StartupRevealPhase.occluding) {
      return;
    }
    if (reduceMotion) {
      _transition(StartupRevealPhase.exiting);
      return;
    }
    _transition(StartupRevealPhase.revealing);
  }

  /// Normal fast-path: the target content is ready and the reveal may end
  /// early instead of playing the full teaser. Quick data success must not
  /// wait for the full animation.
  void markContentReady() {
    if (_disposed ||
        _phase == StartupRevealPhase.done ||
        _phase == StartupRevealPhase.exiting) {
      return;
    }
    _transition(StartupRevealPhase.exiting);
  }

  /// The reveal animation finished; the layer starts its exit fade.
  void markRevealAnimationDone() {
    if (_disposed || _phase != StartupRevealPhase.revealing) {
      return;
    }
    _transition(StartupRevealPhase.exiting);
  }

  /// The exit fade finished; the layer removes itself.
  void markExitFinished() {
    if (_disposed || _phase != StartupRevealPhase.exiting) {
      return;
    }
    if (const bool.fromEnvironment('STARTUP_DBG')) {
      // ignore: avoid_print
      print('DBG markExitFinished called');
    }
    _transition(StartupRevealPhase.done);
  }

  /// Entering background collapses the layer: no replay after return, no
  /// queued work to re-occlude content.
  void handleBackgrounded() {
    if (_disposed || isDone) {
      return;
    }
    _transition(StartupRevealPhase.done);
  }

  void _transition(StartupRevealPhase next) {
    if (_disposed || _phase == next || _phase == StartupRevealPhase.done) {
      return;
    }
    _phase = next;
    _generation += 1;
    notifyListeners();
    if (next == StartupRevealPhase.done) {
      StartupRevealController.onDone?.call();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Application-lifetime presentation controller; created on first read.
final Provider<StartupRevealController> startupRevealControllerProvider =
    Provider<StartupRevealController>((Ref ref) {
      final StartupRevealController controller = StartupRevealController();
      ref.onDispose(controller.dispose);
      return controller;
    });

/// Derived read-only view of the authoritative controller phase. The
/// Notifier's only writer is build(), which copies the controller's current
/// phase and subscribes for the provider's lifetime.
class StartupRevealPhaseController extends Notifier<StartupRevealPhase> {
  @override
  StartupRevealPhase build() {
    final StartupRevealController controller = ref.watch(
      startupRevealControllerProvider,
    );
    controller.addListener(_sync);
    ref.onDispose(() => controller.removeListener(_sync));
    return controller.phase;
  }

  void _sync() {
    final StartupRevealController controller = ref.watch(
      startupRevealControllerProvider,
    );
    if (state != controller.phase) {
      state = controller.phase;
    }
  }
}

final NotifierProvider<StartupRevealPhaseController, StartupRevealPhase>
startupRevealPhaseProvider =
    NotifierProvider<StartupRevealPhaseController, StartupRevealPhase>(
      StartupRevealPhaseController.new,
    );
