import 'dart:async';

import '../../model/album_models.dart';

/// The slot tracks actual work, not just the UI Future. A stuck cancelled
/// worker cannot be bypassed by reopening the picker or spawning more work.
final class ExportScheduler {
  ExportScheduler({this.stopWait = const Duration(seconds: 5)});
  final Duration stopWait;
  _Running? _active;

  Future<AlbumFileLease> run({
    required AlbumCancellation cancellation,
    required Duration timeout,
    required Future<AlbumFileLease> Function() start,
    required Future<void> Function() stop,
  }) async {
    final previous = _active;
    if (previous != null) {
      if (previous.stopDeadline.isCompleted) {
        throw const AlbumFailure('exportUnavailable');
      }
      await Future.any<void>([
        previous.done.future.timeout(
          stopWait,
          onTimeout: () => throw const AlbumFailure('exportUnavailable'),
        ),
        previous.stopDeadline.future.then(
          (_) => throw const AlbumFailure('exportUnavailable'),
        ),
        cancellation.whenCancelled.then(
          (_) => throw const AlbumFailure('cancelled'),
        ),
      ]);
    }
    if (cancellation.cancelled) throw const AlbumFailure('cancelled');
    // Several waiting sessions must not claim the same newly released slot.
    if (_active != null) throw const AlbumFailure('exportUnavailable');
    final running = _Running();
    _active = running;
    final result = Completer<AlbumFileLease>();
    void cancel(String code) {
      if (result.isCompleted) return;
      running.stopTimer = Timer(
        stopWait,
        () => running.stopDeadline.complete(),
      );
      result.completeError(AlbumFailure(code));
      unawaited(stop().catchError((Object _) {}));
    }

    final timer = Timer(timeout, () => cancel('timeout'));
    unawaited(cancellation.whenCancelled.then((_) => cancel('cancelled')));
    unawaited(() async {
      try {
        final lease = await start();
        if (result.isCompleted || cancellation.cancelled) {
          await lease.release();
          if (!result.isCompleted) {
            result.completeError(const AlbumFailure('cancelled'));
          }
        } else {
          result.complete(lease);
        }
      } catch (error, stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      } finally {
        timer.cancel();
        running.stopTimer?.cancel();
        if (identical(_active, running)) _active = null;
        running.done.complete();
      }
    }());
    return result.future;
  }
}

final class _Running {
  final done = Completer<void>();
  final stopDeadline = Completer<void>();
  Timer? stopTimer;
}
