import 'dart:async';

abstract interface class RequestCancellation {
  bool get isCancelled;

  Future<void> get whenCancelled;

  void throwIfCancelled();

  void Function() addCancelListener(void Function() listener);
}

abstract interface class RequestCancellationController {
  RequestCancellation get signal;

  void cancel();
}

final class DefaultRequestCancellationController
    implements RequestCancellationController, RequestCancellation {
  final Completer<void> _cancelled = Completer<void>();
  final Set<void Function()> _listeners = <void Function()>{};

  @override
  RequestCancellation get signal => this;

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  @override
  void cancel() {
    if (isCancelled) {
      return;
    }
    _cancelled.complete();
    final List<void Function()> listeners = _listeners.toList(growable: false);
    _listeners.clear();
    for (final void Function() listener in listeners) {
      listener();
    }
  }

  @override
  void throwIfCancelled() {
    if (isCancelled) {
      throw const RequestCancelledException();
    }
  }

  @override
  void Function() addCancelListener(void Function() listener) {
    if (isCancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

final class RequestCancelledException implements Exception {
  const RequestCancelledException();

  @override
  String toString() => 'RequestCancelledException';
}
