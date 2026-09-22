import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/network/auth_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_commit_coordinator.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_models.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_store.dart';
import 'package:wanandroid_flutter/src/data/network/session/web_cookie.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_auth_repository.dart';
import 'package:wanandroid_flutter/src/data/storage/session_storage.dart';
import 'package:wanandroid_flutter/src/model/user.dart';

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
  test('parses dashed Netscape Expires dates emitted by wanandroid', () {
    final cookie = WebCookie.parse(
      'loginUserName=fixture-user; '
      'Expires=Wed, 21-Oct-2026 13:36:34 GMT; Path=/',
      apiHost: 'wanandroid.com',
    );
    expect(cookie, isNotNull);
    expect(cookie!.persistent, isTrue);
    expect(cookie.expired, isFalse);
    expect(
      cookie.expiresAtMilliseconds,
      DateTime.utc(2026, 10, 21, 13, 36, 34).millisecondsSinceEpoch,
    );
  });

  test('session cookies without expiry stay alive in memory only', () {
    final cookie = WebCookie.parse(
      'JSESSIONID=ABC123; Path=/; Secure; HttpOnly',
      apiHost: 'wanandroid.com',
    );
    expect(cookie, isNotNull);
    expect(cookie!.persistent, isFalse);
    expect(cookie.expired, isFalse);
    expect(cookie.expiresAtMilliseconds, 4102444800000);
  });

  test(
    'login commit keeps session cookies and persists only persistent ones',
    () async {
      final _MemoryStorage storage = _MemoryStorage();
      final SessionStore store = _store(storage);
      final SessionRequest request = await store.beginLogin();
      store.observeResponseCookies(request, <WebCookie>[
        WebCookie(
          name: 'JSESSIONID',
          value: 'session-value',
          domain: 'wanandroid.com',
          path: '/',
          expiresAtMilliseconds: 4102444800000,
          persistent: false,
        ),
        WebCookie(
          name: 'loginUserName',
          value: 'fixture-user',
          domain: 'wanandroid.com',
          path: '/',
          expiresAtMilliseconds: DateTime.utc(
            2026,
            10,
            21,
          ).millisecondsSinceEpoch,
          persistent: true,
        ),
      ]);
      final bool committed = await store.commitLogin(
        request,
        const User(id: 7, username: 'user'),
      );
      expect(committed, isTrue);
      expect(store.snapshot.authenticated, isTrue);
      // Session cookies survive in memory for subsequent normal requests
      // (the LOGIN-mode request itself carries none, by contract).
      final SessionRequest normal = store.capture();
      expect(
        store.cookieHeader(normal, Uri.parse('https://wanandroid.com/')),
        contains('JSESSIONID=session-value'),
      );
      // ...but the persisted payload only holds persistent cookies.
      expect(storage.payload, isNot(contains('JSESSIONID')));
      expect(storage.payload, contains('loginUserName'));
    },
  );

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

  test('Max-Age zero is represented as an expired deletion cookie', () {
    final WebCookie? cookie = WebCookie.parse(
      'JSESSIONID=; Max-Age=0; Path=/',
      apiHost: SessionStore.apiHost,
    );

    expect(cookie, isNotNull);
    expect(cookie!.persistent, isTrue);
    expect(cookie.expired, isTrue);
  });

  test('invalid user identity cannot be committed', () async {
    final SessionStore store = _store(_MemoryStorage());
    final DefaultAuthRepository repository = DefaultAuthRepository(
      sessionStore: store,
      source: _InvalidUserAuthSource(store),
      coordinator: SessionCommitCoordinator(),
    );

    final DataResult<void> result = await repository.login(
      '13800138000',
      'secret',
    );

    expect(result, const DataFailure<void>(DataError.sessionChanged));
    expect(store.snapshot.phase, SessionPhase.guest);
    expect(store.snapshot.user, isNull);
  });

  test('cancelling login aborts its session before returning', () async {
    final SessionStore store = _store(_MemoryStorage());
    final _CancellationAuthSource source = _CancellationAuthSource(store);
    final DefaultAuthRepository repository = DefaultAuthRepository(
      sessionStore: store,
      source: source,
      coordinator: SessionCommitCoordinator(),
    );
    final DefaultRequestCancellationController cancellation =
        DefaultRequestCancellationController();

    final Future<DataResult<void>> login = repository.login(
      '13800138000',
      'secret',
      cancellation: cancellation.signal,
    );
    await source.started.future;
    cancellation.cancel();

    await expectLater(login, throwsA(isA<RequestCancelledException>()));
    expect(store.snapshot.phase, SessionPhase.guest);
    expect(store.snapshot.user, isNull);
  });

  test('failure cleanup completes before a queued retry starts', () async {
    final _NthBlockingStorage storage = _NthBlockingStorage(blockAtWrite: 2);
    final SessionStore store = _store(storage);
    final _SequenceAuthSource source = _SequenceAuthSource(store);
    final DefaultAuthRepository repository = DefaultAuthRepository(
      sessionStore: store,
      source: source,
      coordinator: SessionCommitCoordinator(),
    );

    final Future<DataResult<void>> first = repository.login(
      '13800138000',
      'wrong',
    );
    await storage.blocked.future;
    final Future<DataResult<void>> retry = repository.login(
      '13800138000',
      'secret',
    );
    await Future<void>.delayed(Duration.zero);
    expect(source.loginCalls, 1);

    storage.release();
    expect(await first, isA<DataFailure<void>>());
    expect(await retry, isA<DataSuccess<void>>());
    expect(source.loginCalls, 2);
    expect(store.snapshot.phase, SessionPhase.authenticated);
  });
}

class _MemoryStorage implements SessionStorage {
  String? payload;

  @override
  Future<String?> read() async => payload;

  @override
  Future<void> write(String? value) async => payload = value;
}

class _NthBlockingStorage implements SessionStorage {
  _NthBlockingStorage({required this.blockAtWrite});

  final int blockAtWrite;
  final Completer<void> blocked = Completer<void>();
  final Completer<void> _release = Completer<void>();
  int writes = 0;
  String? payload;

  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<String?> read() async => payload;

  @override
  Future<void> write(String? value) async {
    writes++;
    if (writes == blockAtWrite) {
      if (!blocked.isCompleted) blocked.complete();
      await _release.future;
    }
    payload = value;
  }
}

class _StaticAuthSource implements AuthNetworkDataSource {
  _StaticAuthSource(this.store);

  final SessionStore store;

  @override
  Future<Map<String, dynamic>> login(
    String username,
    String password,
    Object? session,
    RequestCancellation cancellation,
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
    RequestCancellation cancellation,
  ) async => <String, dynamic>{'errorCode': -1, 'data': null};
}

class _ExpiredAuthSource extends _StaticAuthSource {
  _ExpiredAuthSource(super.store);

  @override
  Future<Map<String, dynamic>> userInfo(Object? session) async =>
      <String, dynamic>{'errorCode': -1001, 'data': null};
}

class _InvalidUserAuthSource extends _StaticAuthSource {
  _InvalidUserAuthSource(super.store);

  @override
  Future<Map<String, dynamic>> login(
    String username,
    String password,
    Object? session,
    RequestCancellation cancellation,
  ) async {
    store.observeResponseCookies(session as SessionRequest, <WebCookie>[
      WebCookie(
        name: 'JSESSIONID',
        value: 'invalid-user-session',
        domain: SessionStore.apiHost,
        path: '/',
        expiresAtMilliseconds: DateTime.now()
            .toUtc()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
        persistent: true,
      ),
    ]);
    return <String, dynamic>{
      'errorCode': 0,
      'data': <String, Object?>{'id': 0, 'username': username},
    };
  }
}

class _CancellationAuthSource extends _StaticAuthSource {
  _CancellationAuthSource(super.store);

  final Completer<void> started = Completer<void>();

  @override
  Future<Map<String, dynamic>> login(
    String username,
    String password,
    Object? session,
    RequestCancellation cancellation,
  ) async {
    started.complete();
    await cancellation.whenCancelled;
    throw const RequestCancelledException();
  }
}

class _SequenceAuthSource extends _StaticAuthSource {
  _SequenceAuthSource(super.store);

  int loginCalls = 0;

  @override
  Future<Map<String, dynamic>> login(
    String username,
    String password,
    Object? session,
    RequestCancellation cancellation,
  ) {
    loginCalls++;
    if (loginCalls == 1) {
      return Future<Map<String, dynamic>>.value(<String, dynamic>{
        'errorCode': -1,
        'data': null,
      });
    }
    return super.login(username, password, session, cancellation);
  }
}
