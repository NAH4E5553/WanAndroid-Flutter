import 'dart:async';

import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/diagnostics/startup_metrics.dart';
import 'package:wanandroid_flutter/src/core/startup/startup_reveal_controller.dart';

/// Full-screen startup layer: mirrors the static native launch screen on the
/// first frame, plays the single lightweight reveal animation, then removes
/// itself so the restored application (whatever route it restored to) takes
/// over. While present it blocks hits, focus and semantics on the content
/// below; business initialization continues underneath the whole time.
class StartupRevealLayer extends ConsumerStatefulWidget {
  const StartupRevealLayer({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<StartupRevealLayer> createState() => _StartupRevealLayerState();
}

/// Frame-driven presentation: the controller holds NO timers. The reveal
/// completes when real painted frames have covered its full duration
/// (FrameTiming callbacks); the exit fade completes via its own animation
/// callback. Every transition notifies listeners, and the layer rebuilds
/// through a ListenableBuilder — so each handoff step schedules and paints
/// its own real frame, without depending on timer scheduling that can stall
/// in reduced-animation or frozen-frame environments.
class _StartupRevealLayerState extends ConsumerState<StartupRevealLayer>
    with WidgetsBindingObserver {
  late final StartupRevealController _controller = ref.read(
    startupRevealControllerProvider,
  );
  int? _revealStartedRasterMicros;
  Timer? _revealTimer;
  Timer? _exitConvergenceTimer;
  bool _bridged = false;
  bool _firstFrameSent = false;
  bool _exitAnchored = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(_revealFrameTimings);
  }

  /// Natural reveal completion: measured entirely in the MONOTONIC
  /// rasterFinish domain (never wall time, never the scheduler's animation
  /// clock — mixing epochs makes the first engine report look like the whole
  /// budget has elapsed). The origin is the first reported revealing frame in
  /// that same domain, so a report at 100ms of a 480ms reveal keeps the
  /// phase in revealing.
  void _revealFrameTimings(List<FrameTiming> timings) {
    if (_controller.phase != StartupRevealPhase.revealing) {
      return;
    }
    for (final FrameTiming timing in timings) {
      final int raster = timing.timestampInMicroseconds(
        FramePhase.rasterFinish,
      );
      _revealStartedRasterMicros ??= raster;
      if (raster - _revealStartedRasterMicros! >=
          _controller.revealDuration.inMicroseconds) {
        _controller.markRevealAnimationDone();
        return;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bridged) {
      return;
    }
    _bridged = true;
    // Register the process-wide instance for the home ViewModel's covered
    // predicate (core reads it without importing app modules); unregister on
    // dispose so absent layers never occlude.
    StartupRevealController.instance = _controller;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || _firstFrameSent) {
        return;
      }
      _firstFrameSent = true;
      _controller.markFirstFrame(
        reduceMotion: MediaQuery.disableAnimationsOf(context),
      );
      // Bounded reveal watchdog — runs in EVERY environment (no env branch):
      // engines that deliver FrameTiming complete the reveal via the monotonic
      // callback first and this never fires; schedulers without timing
      // delivery still converge. Cancelled on dispose.
      _revealTimer = Timer(_controller.revealDuration, () {
        if (mounted && _controller.phase == StartupRevealPhase.revealing) {
          _controller.markRevealAnimationDone();
        }
      });
      // Bounded whole-reveal watchdog — also runs in EVERY environment as the
      // final safety net (fade onEnd, monotonic completion and this all
      // converge to the same terminal; every path is idempotent). Cancelled
      // on dispose; no timers outlive the layer.
      _exitConvergenceTimer = Timer(
        _controller.revealDuration + _controller.exitDuration,
        () {
          if (mounted && _controller.phase != StartupRevealPhase.done) {
            _controller.handleBackgrounded();
          }
        },
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _controller.handleBackgrounded();
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        // Brief inactive (permission dialogs, system sheets) must not
        // collapse or replay the reveal.
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SchedulerBinding.instance.removeTimingsCallback(_revealFrameTimings);
    _revealTimer?.cancel();
    _exitConvergenceTimer?.cancel();
    if (identical(StartupRevealController.instance, _controller)) {
      StartupRevealController.instance = null;
    }
    // Layer unmounted while the reveal was still running: converge the
    // controller so a later remount observes the terminal state instead of a
    // stuck in-flight phase (the overlay is gone with this element either
    // way).
    _controller.handleBackgrounded();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The whole layer sits inside a ListenableBuilder on the authoritative
    // controller: every transition marks this tree dirty AND the framework
    // schedules a frame by itself, so each handoff paints a real frame even
    // when no other ticker is running (the reduce-motion path included).
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? _) {
        final StartupRevealPhase phase = _controller.phase;
        if (phase == StartupRevealPhase.done && !_exitAnchored) {
          _exitAnchored = true;
          // Anchor the exit to the raster of the first frame that no longer
          // paints the layer — the removal call time is not "displayed".
          StartupMetrics.instance.frame(
            'startup_layer_exit',
            stillValid: () => _controller.isDone,
          );
        }
        final bool covered = phase != StartupRevealPhase.done;
        return Stack(
          textDirection: TextDirection.ltr,
          children: <Widget>[
            // The gate wrappers around the content are ALWAYS present and
            // only flip their flags at the handoff, so the content's parent
            // chain never changes shape: Element/State identity and the
            // Router subtree survive. The splash overlay is a later Stack
            // sibling; its removal cannot re-parent the content.
            FocusScope(
              canRequestFocus: !covered,
              child: Focus(
                canRequestFocus: !covered,
                descendantsAreFocusable: !covered,
                child: ExcludeSemantics(
                  excluding: covered,
                  child: IgnorePointer(ignoring: covered, child: widget.child),
                ),
              ),
            ),
            if (covered)
              Positioned.fill(
                key: const ValueKey<String>('startup-overlay'),
                // BlockSemantics keeps the covered content out of the
                // semantics tree while the overlay is up: ExcludeSemantics on
                // the content alone does not retract an already-built
                // subtree.
                child: BlockSemantics(
                  blocking: true,
                  child: AbsorbPointer(
                    absorbing: true,
                    child: _StartupSplashView(
                      phase: phase,
                      controller: _controller,
                      background: _nativeBackground(
                        MediaQuery.platformBrightnessOf(context),
                      ),
                      iconSize: defaultTargetPlatform == TargetPlatform.iOS
                          ? 76
                          : 96,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Native launch screens per platform: Android follows the system light/dark
/// resource pair; the iOS launch storyboard is a static white background, so
/// the Flutter start screen stays white there regardless of brightness until
/// the restored theme takes over after the reveal.
Color _nativeBackground(Brightness brightness) {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return const Color(0xFFFFFFFF);
  }
  return brightness == Brightness.dark
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);
}

class _StartupSplashView extends StatelessWidget {
  const _StartupSplashView({
    required this.phase,
    required this.controller,
    required this.background,
    required this.iconSize,
  });

  final StartupRevealPhase phase;
  final StartupRevealController controller;
  final Color background;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final bool exiting = phase == StartupRevealPhase.exiting;
    // The whole splash tree is STRUCTURALLY CONSTANT for the layer lifetime:
    // the fade Opacity and the scale AnimatedScale are always present and
    // only their targets change, so no implicit-animation State is ever
    // re-created and no phase boundary can snap the icon. The scale keeps its
    // current value through the exit (the fade hides the icon anyway), so an
    // early content-ready handoff preserves whatever mid-reveal scale was
    // painted last.
    // The fade wraps the WHOLE splash (background included): during exit the
    // target page shows through the blended splash instead of a hard cut at
    // removal. The tree stays structurally constant — Opacity > ColoredBox >
    // Center > AnimatedScale — so no phase boundary re-creates any animation
    // State (the early-exit scale-continuity contract).
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1, end: exiting ? 0 : 1),
      duration: controller.exitDuration,
      onEnd: exiting ? controller.markExitFinished : null,
      builder: (BuildContext context, double opacity, Widget? child) => Opacity(
        opacity: opacity,
        child: ColoredBox(
          key: const ValueKey<String>('startup-splash-background'),
          color: background,
          child: Center(child: child),
        ),
      ),
      child: AnimatedScale(
        scale: phase == StartupRevealPhase.occluding ? 1 : 1.08,
        duration: controller.revealDuration,
        curve: Curves.easeOutCubic,
        child: CustomPaint(
          size: Size.square(iconSize),
          painter: const _LauncherGlyphPainter(),
        ),
      ),
    );
  }
}

/// Replicates the frozen launcher glyph geometry from
/// `tool/generate_launcher_icons.dart` (108-unit viewport; blue field with
/// two white pages and blue rules) so the first Flutter frame shows the same
/// unmasked composition as the native static screen.
class _LauncherGlyphPainter extends CustomPainter {
  const _LauncherGlyphPainter();

  static const Color _blue = Color(0xFF465CFF);
  static const Color _white = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.width / 108;
    final Paint paint = Paint();
    void draw(double left, double top, double right, double bottom, Color c) {
      paint.color = c;
      canvas.drawRect(
        Rect.fromLTRB(left * scale, top * scale, right * scale, bottom * scale),
        paint,
      );
    }

    draw(0, 0, 108, 108, _blue);
    draw(24, 28, 49, 78, _white);
    draw(59, 28, 84, 78, _white);
    draw(29, 36, 44, 40, _blue);
    draw(29, 46, 44, 50, _blue);
    draw(64, 36, 79, 40, _blue);
    draw(64, 46, 79, 50, _blue);
  }

  @override
  bool shouldRepaint(covariant _LauncherGlyphPainter oldDelegate) => false;
}
