import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/network/auth_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_commit_coordinator.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_models.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_store.dart';
import 'package:wanandroid_flutter/src/data/network/session/web_cookie.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_auth_repository.dart';
import 'package:wanandroid_flutter/src/data/storage/session_storage.dart';

class _BlockingStorage implements SessionStorage {
  _BlockingStorage();

  String? payload;
  Completer<void>? gate;

  void block() => gate = Completer<void>();

  void release() {
    final Completer<void>? pending = gate;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  @override
  Future<String?> read() async => payload;

  @override
  Future<void> write(String? value) async {
    final Completer<void>? pending = gate;
    if (pending != null) {
      await pending.future;
    }
    payload = value;
  }
}

SessionStore _store(SessionStorage storage) => SessionStore(storage: storage);

void main() {
  test('delayed login write finishes before a queued logout runs', () async {
    final _BlockingStorage storage = _BlockingStorage();
    final SessionStore store = _store(storage);
    final DefaultAuthRepository repository = DefaultAuthRepository(
      sessionStore: store,
      source: _StaticAuthSource(store),
      coordinator: SessionCommitCoordinator(),
    );
    storage.block();
    final Future<DataResult<void>> login = repository.login(
      '13800138000',
      'secret',
    );
    // The login write is still blocked on storage; the logout intent must
    // queue behind it through the coordinator.
    final List<String> order = <String>[];
    final Future<LogoutOutcome> logout = repository.logout().then((
      LogoutOutcome outcome,
    ) {
      order.add('logout');
      return outcome;
    });
    await Future<void>.delayed(Duration.zero);
    expect(store.snapshot.phase, isNot(SessionPhase.authenticated));
    storage.release();
    final DataResult<void> loginResult = await login;
    expect(loginResult, isA<DataSuccess<void>>());
    expect(store.snapshot.phase, SessionPhase.authenticated);
    final LogoutOutcome outcome = await logout;
    order.add('done');
    expect(order, <String>['logout', 'done']);
    expect(outcome.localDetached, isTrue);
    expect(store.snapshot.phase, SessionPhase.guest);
  });

  test('login failure aborts and keeps the previous guest state', () async {
    final SessionStore store = _store(_MemoryStorage());
    final DefaultAuthRepository repository = DefaultAuthRepository(
      sessionStore: store,
      source: _FailingAuthSource(store),
      coordinator: SessionCommitCoordinator(),
    );
    final DataResult<void> result = await repository.login(
      '13800138000',
      'secret',
    );
    expect(result, isA<DataFailure<void>>());
    expect(store.snapshot.phase, SessionPhase.guest);
  });

  test('persisted session restores to verifying and verifies', () async {
    final _MemoryStorage storage = _MemoryStorage();
    final SessionStore store = _store(storage);
    final _StaticAuthSource source = _StaticAuthSource(store);
    final DefaultAuthRepository repository = DefaultAuthRepository(
      sessionStore: store,
      source: source,
      coordinator: SessionCommitCoordinator(),
    );
    final DataResult<void> login = await repository.login(
      '13800138000',
      'secret',
    );
    expect(login, isA<DataSuccess<void>>());
    final String persisted = storage.payload!;
    expect(persisted, contains('cookies'));

    // A fresh store represents a restarted process.
    final SessionStore restarted = _store(storage);
    final DefaultAuthRepository restoredRepository = DefaultAuthRepository(
      sessionStore: restarted,
      source: source,
      coordinator: SessionCommitCoordinator(),
    );
    final DataResult<void> restored = await restoredRepository.restore();
    expect(restored, isA<DataSuccess<void>>());
    expect(restarted.snapshot.phase, SessionPhase.authenticated);
    expect(restarted.snapshot.user?.username, '13800138000');
  });

  test('server expiry during restore clears the session', () async {
    final _MemoryStorage storage = _MemoryStorage();
    final SessionStore store = _store(storage);
    final _ExpiredAuthSource source = _ExpiredAuthSource(store);
    final DefaultAuthRepository repository = DefaultAuthRepository(
      sessionStore: store,
      source: source,
      coordinator: SessionCommitCoordinator(),
    );
    // Seed a persisted session manually through a login, then restart.
    await repository.login('13800138000', 'secret');
    final SessionStore restarted = _store(storage);
    final DefaultAuthRepository restoredRepository = DefaultAuthRepository(
      sessionStore: restarted,
      source: source,
      coordinator: SessionCommitCoordinator(),
    );
    final DataResult<void> restored = await restoredRepository.restore();
    expect(restored, isA<DataFailure<void>>());
    expect(restarted.snapshot.phase, SessionPhase.guest);
  });
}

class _MemoryStorage implements SessionStorage {
  String? payload;

  @override
  Future<String?> read() async => payload;

  @override
  Future<void> write(String? value) async => payload = value;
}

class _StaticAuthSource implements AuthNetworkDataSource {
  _StaticAuthSource(this.store);

  final SessionStore store;

  @override
  Future<Map<String, dynamic>> login(
    String username,
    String password,
    Object? session,
  ) async {
    // The real interceptor observes Set-Cookie on the wire; this fake plays
    // the same role for the unit test.
    store.observeResponseCookies(session as SessionRequest, <WebCookie>[
      WebCookie(
        name: 'JSESSIONID',
        value: 'test-session',
        domain: 'wanandroid.com',
        path: '/',
        expiresAtMilliseconds: DateTime.now()
            .toUtc()
            .add(const Duration(days: 7))
            .millisecondsSinceEpoch,
        persistent: true,
      ),
    ]);
    return <String, dynamic>{
      'errorCode': 0,
      'data': <String, Object?>{'id': 7, 'username': username},
    };
  }

  @override
  Future<Map<String, dynamic>> userInfo(Object? session) async =>
      <String, dynamic>{
        'errorCode': 0,
        'data': <String, Object?>{
          'userInfo': <String, Object?>{'id': 7, 'username': '13800138000'},
        },
      };

  @override
  Future<Map<String, dynamic>> logout(Object? session) async =>
      <String, dynamic>{'errorCode': 0, 'data': null};
}

class _FailingAuthSource extends _StaticAuthSource {
  _FailingAuthSource(super.store);

  @override
  Future<Map<String, dynamic>> login(
    String username,
    String password,
    Object? session,
  ) async => <String, dynamic>{'errorCode': -1, 'data': null};
}

class _ExpiredAuthSource extends _StaticAuthSource {
  _ExpiredAuthSource(super.store);

  @override
  Future<Map<String, dynamic>> userInfo(Object? session) async =>
      <String, dynamic>{'errorCode': -1001, 'data': null};
}
