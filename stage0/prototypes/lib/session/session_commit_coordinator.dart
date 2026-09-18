import 'dart:async';
import 'dart:convert';

abstract interface class SessionStorage {
  Future<String?> read();

  Future<void> write(String? value);
}

enum SessionPhase {
  guest,
  transitioning,
  authenticated,
  unverified,
  storageError,
}

final class SessionSnapshot {
  const SessionSnapshot({
    required this.phase,
    required this.generation,
    this.accountId,
  });

  const SessionSnapshot.guest()
    : phase = SessionPhase.guest,
      generation = 0,
      accountId = null;

  final SessionPhase phase;
  final int generation;
  final String? accountId;
}

final class ReplacementTicket {
  ReplacementTicket._({
    required this.owner,
    required this.commitId,
    required this.generation,
    required this.ready,
  });

  final int commitId;
  final int generation;
  final Future<bool> ready;
  final Object owner;
  bool _used = false;
}

/// Stage-0 prototype for serializing all durable session transitions.
///
/// A replacement first persists a tombstone. A later login write can therefore
/// fail without making a superseded account recoverable after restart, PROVIDED
/// the tombstone succeeded. Failed cleanup cannot revoke an old disk value.
final class SessionCommitCoordinator {
  SessionCommitCoordinator(this._storage);

  final SessionStorage _storage;
  Future<void> _tail = Future<void>.value();
  int _latestCommitId = 0;
  int _generation = 0;
  bool _replacementStarted = false;
  SessionSnapshot _snapshot = const SessionSnapshot.guest();

  SessionSnapshot get snapshot => _snapshot;

  ReplacementTicket startReplacement() {
    _replacementStarted = true;
    final commitId = ++_latestCommitId;
    final generation = ++_generation;
    _snapshot = SessionSnapshot(
      phase: SessionPhase.transitioning,
      generation: generation,
    );
    final ready = _enqueue(() async {
      if (commitId != _latestCommitId) return false;
      try {
        await _storage.write(null);
      } on Object {
        if (commitId == _latestCommitId) {
          _snapshot = SessionSnapshot(
            phase: SessionPhase.storageError,
            generation: generation,
          );
        }
        return false;
      }
      if (commitId != _latestCommitId) return false;
      _snapshot = SessionSnapshot(
        phase: SessionPhase.guest,
        generation: generation,
      );
      return true;
    });
    return ReplacementTicket._(
      owner: this,
      commitId: commitId,
      generation: generation,
      ready: ready,
    );
  }

  Future<bool> commitLogin(ReplacementTicket ticket, String accountId) async {
    if (!identical(ticket.owner, this) || ticket._used || accountId.isEmpty) {
      return false;
    }
    ticket._used = true;
    if (!await ticket.ready) return false;
    var accepted = false;
    await _enqueue(() async {
      if (ticket.commitId != _latestCommitId) return;
      final payload = jsonEncode(<String, Object>{
        'commitId': ticket.commitId,
        'generation': ticket.generation,
        'accountId': accountId,
      });
      try {
        await _storage.write(payload);
      } on Object {
        if (ticket.commitId == _latestCommitId) {
          _snapshot = SessionSnapshot(
            phase: SessionPhase.storageError,
            generation: ticket.generation,
          );
        }
        return;
      }
      if (ticket.commitId != _latestCommitId) return;
      _snapshot = SessionSnapshot(
        phase: SessionPhase.authenticated,
        generation: ticket.generation,
        accountId: accountId,
      );
      accepted = true;
    });
    return accepted;
  }

  Future<bool> logout() => startReplacement().ready;

  Future<void> restore() {
    // Restore is bootstrap-only. It must never supersede a user intent, even
    // when that intent's durable cleanup failed. Retry via a new replacement.
    if (_replacementStarted) return _tail;
    final commitId = ++_latestCommitId;
    final generation = ++_generation;
    _snapshot = SessionSnapshot(
      phase: SessionPhase.transitioning,
      generation: generation,
    );
    return _enqueue(() async {
      try {
        final payload = await _storage.read();
        if (commitId != _latestCommitId) return;
        if (payload == null) {
          _snapshot = SessionSnapshot(
            phase: SessionPhase.guest,
            generation: generation,
          );
          return;
        }
        final decoded = jsonDecode(payload) as Map<String, Object?>;
        final accountId = decoded['accountId'] as String?;
        if (accountId == null || accountId.isEmpty) {
          throw const FormatException('Missing account identity');
        }
        _snapshot = SessionSnapshot(
          phase: SessionPhase.unverified,
          generation: generation,
          accountId: accountId,
        );
      } on Object {
        if (commitId == _latestCommitId) {
          _snapshot = SessionSnapshot(
            phase: SessionPhase.storageError,
            generation: generation,
          );
        }
      }
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
