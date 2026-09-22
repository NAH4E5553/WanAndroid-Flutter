import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_commit_coordinator.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_interceptor.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_models.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_store.dart';
import 'package:wanandroid_flutter/src/data/network/session/web_cookie.dart';
import 'package:wanandroid_flutter/src/data/storage/session_storage.dart';
import 'package:wanandroid_flutter/src/model/user.dart';

void main() {
  test(
    'SESSION-01 normal response rotates cookies through the serial coordinator',
    () async {
      final _MemoryStorage storage = _MemoryStorage();
      final SessionStore store = SessionStore(storage: storage);
      await _authenticate(store);
      final SessionCommitCoordinator coordinator = SessionCommitCoordinator();
      final Dio dio = _dio(
        store,
        coordinator,
        body: <String, Object?>{'errorCode': 0, 'data': <String, Object?>{}},
        setCookies: const <String>[
          'JSESSIONID=rotated-session; Max-Age=3600; Path=/; Secure; HttpOnly',
        ],
      );
      addTearDown(dio.close);

      final SessionRequest request = store.capture();
      await dio.get<Object?>(
        'article/list/0/json',
        options: Options(
          extra: <String, Object?>{SessionInterceptor.sessionExtraKey: request},
        ),
      );
      await coordinator.run<void>(() async {});

      expect(
        store.cookieHeader(
          store.capture(),
          Uri.parse('https://wanandroid.com/'),
        ),
        contains('JSESSIONID=rotated-session'),
      );
      expect(storage.payload, contains('rotated-session'));
    },
  );

  test('SESSION-01 minus 1001 on a normal API response expires the current session', () async {
    final SessionStore store = SessionStore(storage: _MemoryStorage());
    await _authenticate(store);
    final SessionCommitCoordinator coordinator = SessionCommitCoordinator();
    final Dio dio = _dio(
      store,
      coordinator,
      body: <String, Object?>{'errorCode': -1001, 'data': null},
    );
    addTearDown(dio.close);

    final SessionRequest request = store.capture();
    await dio.get<Object?>(
      'article/list/0/json',
      options: Options(
        extra: <String, Object?>{SessionInterceptor.sessionExtraKey: request},
      ),
    );
    await coordinator.run<void>(() async {});

    expect(store.snapshot.phase, SessionPhase.guest);
    expect(store.snapshot.notice, SessionNotice.expired);
  });

  test(
    'SESSION-01 HTTP 401 expires the current session through Dio onError',
    () async {
      final SessionStore store = SessionStore(storage: _MemoryStorage());
      await _authenticate(store);
      final SessionCommitCoordinator coordinator = SessionCommitCoordinator();
      final Dio dio = _dio(
        store,
        coordinator,
        body: <String, Object?>{'errorCode': 0, 'data': null},
        statusCode: 401,
      );
      addTearDown(dio.close);

      await expectLater(
        dio.get<Object?>(
          'article/list/0/json',
          options: Options(
            extra: <String, Object?>{
              SessionInterceptor.sessionExtraKey: store.capture(),
            },
          ),
        ),
        throwsA(isA<DioException>()),
      );
      await coordinator.run<void>(() async {});

      expect(store.snapshot.phase, SessionPhase.guest);
      expect(store.snapshot.notice, SessionNotice.expired);
    },
  );

  test(
    'SESSION-01 delayed old response cannot expire or rotate a newer session',
    () async {
      final SessionStore store = SessionStore(storage: _MemoryStorage());
      await _authenticate(store);
      final SessionCommitCoordinator coordinator = SessionCommitCoordinator();
      final _DelayedResponseAdapter adapter = _DelayedResponseAdapter(
        <String, Object?>{'errorCode': -1001, 'data': null},
        const <String>[
          'JSESSIONID=stale-session; Max-Age=3600; Path=/; Secure; HttpOnly',
        ],
      );
      final Dio dio = _dio(store, coordinator, adapter: adapter);
      addTearDown(dio.close);

      final SessionRequest oldRequest = store.capture();
      final Future<Response<Object?>> oldResponse = dio.get<Object?>(
        'article/list/0/json',
        options: Options(
          extra: <String, Object?>{
            SessionInterceptor.sessionExtraKey: oldRequest,
          },
        ),
      );
      await adapter.started.future;

      await coordinator.run<void>(() async {
        await _authenticate(
          store,
          user: const User(id: 8, username: 'fixture-user-b'),
          sessionValue: 'new-session',
        );
      });
      adapter.release.complete();
      await oldResponse;
      await coordinator.run<void>(() async {});

      expect(store.snapshot.phase, SessionPhase.authenticated);
      expect(store.snapshot.user?.id, 8);
      final String header = store.cookieHeader(
        store.capture(),
        Uri.parse('https://wanandroid.com/'),
      );
      expect(header, contains('JSESSIONID=new-session'));
      expect(header, isNot(contains('stale-session')));
    },
  );

  test(
    'SESSION-01 Max-Age zero removes the cookie and expires an empty jar',
    () async {
      final SessionStore store = SessionStore(storage: _MemoryStorage());
      await _authenticate(store);
      final SessionCommitCoordinator coordinator = SessionCommitCoordinator();
      final Dio dio = _dio(
        store,
        coordinator,
        body: <String, Object?>{'errorCode': 0, 'data': <String, Object?>{}},
        setCookies: const <String>['JSESSIONID=; Max-Age=0; Path=/'],
      );
      addTearDown(dio.close);

      await dio.get<Object?>(
        'article/list/0/json',
        options: Options(
          extra: <String, Object?>{
            SessionInterceptor.sessionExtraKey: store.capture(),
          },
        ),
      );
      await coordinator.run<void>(() async {});

      expect(store.snapshot.phase, SessionPhase.guest);
      expect(store.snapshot.notice, SessionNotice.expired);
    },
  );
}

Dio _dio(
  SessionStore store,
  SessionCommitCoordinator coordinator, {
  Map<String, Object?> body = const <String, Object?>{},
  List<String> setCookies = const <String>[],
  int statusCode = 200,
  HttpClientAdapter? adapter,
}) {
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: 'https://wanandroid.com/',
      responseType: ResponseType.json,
    ),
  );
  dio.httpClientAdapter =
      adapter ?? _ResponseAdapter(body, setCookies, statusCode);
  dio.interceptors.add(SessionInterceptor(store, coordinator));
  return dio;
}

Future<void> _authenticate(
  SessionStore store, {
  User user = const User(id: 7, username: 'fixture-user'),
  String sessionValue = 'initial-session',
}) async {
  final SessionRequest request = await store.beginLogin();
  store.observeResponseCookies(request, <WebCookie>[
    WebCookie(
      name: 'JSESSIONID',
      value: sessionValue,
      domain: SessionStore.apiHost,
      path: '/',
      expiresAtMilliseconds: DateTime.now()
          .toUtc()
          .add(const Duration(days: 1))
          .millisecondsSinceEpoch,
      persistent: true,
    ),
  ]);
  expect(await store.commitLogin(request, user), isTrue);
}

class _MemoryStorage implements SessionStorage {
  String? payload;

  @override
  Future<String?> read() async => payload;

  @override
  Future<void> write(String? value) async => payload = value;
}

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.body, this.setCookies, this.statusCode);

  final Map<String, Object?> body;
  final List<String> setCookies;
  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      if (setCookies.isNotEmpty) 'set-cookie': setCookies,
    },
  );

  @override
  void close({bool force = false}) {}
}

class _DelayedResponseAdapter implements HttpClientAdapter {
  _DelayedResponseAdapter(this.body, this.setCookies);

  final Map<String, Object?> body;
  final List<String> setCookies;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    started.complete();
    await release.future;
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        'set-cookie': setCookies,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
