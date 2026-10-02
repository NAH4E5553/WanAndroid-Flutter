import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Local, opt-in diagnostics. No business state or user data is stored here.
class StartupMetrics {
  StartupMetrics({
    required this.enabled,
    int Function()? clock,
    void Function(Map<String, Object>)? emit,
  }) : _clock = clock ?? (() => developer.Timeline.now),
       _emit = emit ?? _log;

  static StartupMetrics instance = StartupMetrics(
    enabled: const bool.fromEnvironment('STARTUP_METRICS'),
  );

  final bool enabled;
  final int Function() _clock;
  final void Function(Map<String, Object>) _emit;
  final Set<String> _recorded = <String>{};
  final List<_PendingFrame> _pending = <_PendingFrame>[];
  int? _startedAt;
  bool _attached = false;

  void start() {
    if (!enabled || _startedAt != null) return;
    _startedAt = _clock();
    mark('dart_main');
  }

  void mark(
    String point, {
    String outcome = 'ok',
    int? atMicros,
    int? epochMicros,
  }) {
    if (!enabled || _startedAt == null || _recorded.contains(point)) return;
    final int now = _clock();
    final int at = atMicros ?? now;
    if (at < _startedAt! || at > now) return;
    _recorded.add(point);
    _emit(<String, Object>{
      'schema': 1,
      'point': point,
      'outcome': outcome,
      'dart_us': at - _startedAt!,
      // Host correlates this with a device log marker preceding Launcher input.
      // Subtract batched callback delay, rather than measuring log arrival time.
      'epoch_us':
          epochMicros ?? DateTime.now().microsecondsSinceEpoch - (now - at),
    });
  }

  void attach() {
    if (!enabled || _attached) return;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback(recordTimings);
  }

  /// Called during the build of the actual visible UI, not on HTTP completion.
  void frame(
    String point, {
    required bool Function() stillValid,
    String outcome = 'ok',
  }) {
    if (!enabled ||
        _startedAt == null ||
        _recorded.contains(point) ||
        _recorded.contains('home_terminal_raster')) {
      return;
    }
    final _PendingFrame pending = _PendingFrame(
      point,
      outcome,
      _clock(),
      stillValid,
    );
    _pending.add(pending);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      pending.accepted = pending.stillValid();
    });
  }

  void recordTimings(List<FrameTiming> timings) {
    for (final FrameTiming timing in timings) {
      final int begin = timing.timestampInMicroseconds(FramePhase.buildStart);
      final int end = timing.timestampInMicroseconds(FramePhase.buildFinish);
      final int raster = timing.timestampInMicroseconds(
        FramePhase.rasterFinish,
      );
      final int wall = timing.timestampInMicroseconds(
        FramePhase.rasterFinishWallTime,
      );
      mark('first_raster', atMicros: raster, epochMicros: wall);
      _pending.removeWhere((_PendingFrame pending) {
        if (const bool.fromEnvironment('STARTUP_DBG')) {
          debugPrintSynchronously(
            'DBG rt point=${pending.point} req=${pending.requestedAt} '
            'begin=$begin end=$end accepted=${pending.accepted}',
          );
        }
        if (pending.requestedAt > end) return false;
        if (pending.requestedAt >= begin && pending.accepted) {
          mark(
            pending.point,
            outcome: pending.outcome,
            atMicros: raster,
            epochMicros: wall,
          );
        }
        return true;
      });
    }
    if (_recorded.contains('home_terminal_raster')) detach();
  }

  @visibleForTesting
  int get pendingCount => _pending.length;

  @visibleForTesting
  int get debugNow => _clock();
  @visibleForTesting
  int get recordedCount => _recorded.length;

  void detach() {
    if (_attached) {
      SchedulerBinding.instance.removeTimingsCallback(recordTimings);
    }
    _attached = false;
    _pending.clear();
  }

  static void _log(Map<String, Object> event) {
    debugPrintSynchronously('WAN_STARTUP ${jsonEncode(event)}');
  }
}

class _PendingFrame {
  _PendingFrame(this.point, this.outcome, this.requestedAt, this.stillValid);

  final String point;
  final String outcome;
  final int requestedAt;
  final bool Function() stillValid;
  bool accepted = false;
}
