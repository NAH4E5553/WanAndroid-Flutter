import 'dart:async';

/// Single async gate for login, logout and restore. Every session transition
/// queues here so an old delayed write can never interleave with a newer
/// account intent, per the frozen session contract.
class SessionCommitCoordinator {
  Future<Object?> _tail = Future<Object?>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final Future<Object?> current = _tail;
    final Completer<Object?> gate = Completer<Object?>();
    _tail = gate.future;
    return current.then((_) => operation()).whenComplete(() {
      gate.complete();
    });
  }
}
