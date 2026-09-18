import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_stage0_prototypes/session/session_commit_coordinator.dart';

void main() {
  test('delayed old login cannot survive a later logout', () async {
    final storage = _PausableSessionStorage();
    final coordinator = SessionCommitCoordinator(storage);
    final accountA = coordinator.startReplacement();
    await accountA.ready;

    final pausedA = storage.pauseNextWrite();
    final commitA = coordinator.commitLogin(accountA, 'account-a');
    await pausedA.started;

    final logout = coordinator.logout();
    expect(coordinator.snapshot.phase, SessionPhase.transitioning);
    pausedA.release();

    expect(await commitA, isFalse);
    await logout;
    expect(coordinator.snapshot.phase, SessionPhase.guest);
    expect(storage.value, isNull);

    final restarted = SessionCommitCoordinator(storage);
    await restarted.restore();
    expect(restarted.snapshot.phase, SessionPhase.guest);
    expect(restarted.snapshot.accountId, isNull);
  });

  test('delayed old login is overwritten by the new account', () async {
    final storage = _PausableSessionStorage();
    final coordinator = SessionCommitCoordinator(storage);
    final accountA = coordinator.startReplacement();
    await accountA.ready;

    final pausedA = storage.pauseNextWrite();
    final commitA = coordinator.commitLogin(accountA, 'account-a');
    await pausedA.started;

    final accountB = coordinator.startReplacement();
    pausedA.release();
    expect(await commitA, isFalse);
    await accountB.ready;
    expect(await coordinator.commitLogin(accountB, 'account-b'), isTrue);
    expect(coordinator.snapshot.accountId, 'account-b');

    final restarted = SessionCommitCoordinator(storage);
    await restarted.restore();
    expect(restarted.snapshot.phase, SessionPhase.unverified);
    expect(restarted.snapshot.accountId, 'account-b');
  });

  test(
    'failed successor write leaves a tombstone, never old account data',
    () async {
      final storage = _PausableSessionStorage();
      final coordinator = SessionCommitCoordinator(storage);
      final accountA = coordinator.startReplacement();
      await accountA.ready;

      final pausedA = storage.pauseNextWrite();
      final commitA = coordinator.commitLogin(accountA, 'account-a');
      await pausedA.started;

      final accountB = coordinator.startReplacement();
      pausedA.release();
      expect(await commitA, isFalse);
      await accountB.ready;
      storage.failNextWrite = true;

      expect(await coordinator.commitLogin(accountB, 'account-b'), isFalse);
      expect(coordinator.snapshot.phase, SessionPhase.storageError);
      expect(storage.value, isNull);

      final restarted = SessionCommitCoordinator(storage);
      await restarted.restore();
      expect(restarted.snapshot.phase, SessionPhase.guest);
      expect(restarted.snapshot.accountId, isNull);
    },
  );
  test('failed cleanup blocks login and same-process restore', () async {
    final storage = _PausableSessionStorage()..value = '{"accountId":"old"}';
    final coordinator = SessionCommitCoordinator(storage);
    storage.failNextWrite = true;
    final ticket = coordinator.startReplacement();
    expect(await ticket.ready, isFalse);
    expect(await coordinator.commitLogin(ticket, 'new'), isFalse);
    await coordinator.restore();
    expect(coordinator.snapshot.phase, SessionPhase.storageError);
    expect(coordinator.snapshot.accountId, isNull);
    expect(storage.value, contains('old'));

    // This intentionally demonstrates the limit: failed cleanup was NOT durable.
    final restarted = SessionCommitCoordinator(storage);
    await restarted.restore();
    expect(restarted.snapshot.phase, SessionPhase.unverified);
    expect(restarted.snapshot.accountId, 'old');

    expect(await coordinator.logout(), isTrue);
    await restarted.restore();
    expect(restarted.snapshot.phase, SessionPhase.guest);
  });

  test('restore cannot cancel a queued logout', () async {
    final storage = _PausableSessionStorage();
    final coordinator = SessionCommitCoordinator(storage);
    final ticket = coordinator.startReplacement();
    await ticket.ready;
    final pause = storage.pauseNextWrite();
    final login = coordinator.commitLogin(ticket, 'old');
    await pause.started;
    final logout = coordinator.logout();
    final restore = coordinator.restore();
    pause.release();
    expect(await login, isFalse);
    expect(await logout, isTrue);
    await restore;
    expect(coordinator.snapshot.phase, SessionPhase.guest);
    expect(storage.value, isNull);
  });

  for (final loginSuccessor in [false, true]) {
    test(
      'delayed restore yields to ${loginSuccessor ? "login" : "logout"}',
      () async {
        final storage = _PausableSessionStorage()
          ..value = '{"accountId":"old"}';
        final pause = storage.pauseNextRead();
        final coordinator = SessionCommitCoordinator(storage);
        final restore = coordinator.restore();
        await pause.started;
        final ticket = coordinator.startReplacement();
        pause.release();
        await restore;
        expect(await ticket.ready, isTrue);
        expect(coordinator.snapshot.accountId, isNull);
        if (loginSuccessor) {
          expect(await coordinator.commitLogin(ticket, 'new'), isTrue);
          expect(coordinator.snapshot.accountId, 'new');
        } else {
          expect(coordinator.snapshot.phase, SessionPhase.guest);
        }
      },
    );
  }

  test(
    'stale cleanup failure cannot overwrite a successor transition',
    () async {
      final storage = _PausableSessionStorage()..failNextWrite = true;
      final pause = storage.pauseNextWrite();
      final coordinator = SessionCommitCoordinator(storage);
      final first = coordinator.startReplacement();
      await pause.started;
      final second = coordinator.startReplacement();
      pause.release();
      expect(await first.ready, isFalse);
      expect(await second.ready, isTrue);
      expect(await coordinator.commitLogin(second, 'new'), isTrue);
      expect(coordinator.snapshot.accountId, 'new');
    },
  );

  test(
    'tickets cannot cross coordinators or authorize a second write',
    () async {
      final storage = _PausableSessionStorage();
      final coordinator = SessionCommitCoordinator(storage);
      final ticket = coordinator.startReplacement();
      await ticket.ready;
      final other = SessionCommitCoordinator(_PausableSessionStorage());
      expect(await other.commitLogin(ticket, 'foreign'), isFalse);
      expect(await coordinator.commitLogin(ticket, 'first'), isTrue);
      expect(await coordinator.commitLogin(ticket, 'second'), isFalse);
      expect(coordinator.snapshot.accountId, 'first');
      expect(storage.value, contains('first'));
    },
  );

  test('invalid stored identity fails closed', () async {
    final storage = _PausableSessionStorage()..value = '{"accountId":""}';
    final coordinator = SessionCommitCoordinator(storage);
    await coordinator.restore();
    expect(coordinator.snapshot.phase, SessionPhase.storageError);
    expect(coordinator.snapshot.accountId, isNull);
  });
}

final class _WritePause {
  final Completer<void> _started = Completer<void>();
  final Completer<void> _released = Completer<void>();

  Future<void> get started => _started.future;

  void release() => _released.complete();
}

final class _PausableSessionStorage implements SessionStorage {
  String? value;
  bool failNextWrite = false;
  _WritePause? _nextPause;
  _WritePause? _readPause;

  _WritePause pauseNextRead() => _readPause = _WritePause();

  _WritePause pauseNextWrite() {
    final pause = _WritePause();
    _nextPause = pause;
    return pause;
  }

  @override
  Future<String?> read() async {
    final captured = value;
    final pause = _readPause;
    _readPause = null;
    if (pause != null) {
      pause._started.complete();
      await pause._released.future;
    }
    return captured;
  }

  @override
  Future<void> write(String? value) async {
    final pause = _nextPause;
    _nextPause = null;
    if (pause != null) {
      pause._started.complete();
      await pause._released.future;
    }
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('fixture storage failure');
    }
    this.value = value;
  }
}
