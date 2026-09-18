import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_stage0_prototypes/session/api_cookie_isolation.dart';

void main() {
  final now = DateTime.utc(2026, 9, 18, 12);
  final login = Uri.parse('https://wanandroid.com/user/login');

  test('API cookies obey host path secure and expiry', () {
    final store = ApiCookieIsolationStore()..activateSession('fixture-a');
    final loginRequest = store.capture(login, now: now);
    expect(
      store.acceptSetCookie(
        loginRequest,
        'api_session=fixture-a; Domain=.wanandroid.com; Path=/user; '
        'Secure; Max-Age=60',
        now: now,
      ),
      isTrue,
    );

    expect(
      store
          .capture(
            Uri.parse('https://wanandroid.com/user/lg/userinfo/json'),
            now: now,
          )
          .cookieHeader,
      'api_session=fixture-a',
    );
    expect(
      store
          .capture(
            Uri.parse('https://wanandroid.com/article/list/0/json'),
            now: now,
          )
          .cookieHeader,
      isNull,
    );
    expect(
      store
          .capture(
            Uri.parse('http://wanandroid.com/user/lg/userinfo/json'),
            now: now,
          )
          .cookieHeader,
      isNull,
    );
    expect(
      store
          .capture(
            Uri.parse('https://reader.example/user/lg/userinfo/json'),
            now: now,
          )
          .cookieHeader,
      isNull,
    );
    expect(
      store
          .capture(
            Uri.parse('https://wanandroid.com/user/lg/userinfo/json'),
            now: now.add(const Duration(seconds: 61)),
          )
          .cookieHeader,
      isNull,
    );
  });

  test('invalid domain and malformed values fail closed', () {
    final store = ApiCookieIsolationStore()..activateSession('fixture-a');
    final request = store.capture(login, now: now);
    expect(
      store.acceptSetCookie(
        request,
        'api_session=fixture-a; Domain=example.com; Secure',
        now: now,
      ),
      isFalse,
    );
    expect(store.acceptSetCookie(request, 'bad name=value', now: now), isFalse);
    expect(store.snapshot.cookieCount, 0);
  });

  test('old Set-Cookie cannot cross an account generation', () {
    final store = ApiCookieIsolationStore()..activateSession('fixture-a');
    final accountARequest = store.capture(login, now: now);
    store.activateSession('fixture-b');
    expect(
      store.acceptSetCookie(
        accountARequest,
        'api_session=late-a; Path=/; Secure',
        now: now,
      ),
      isFalse,
    );
    final accountBRequest = store.capture(login, now: now);
    expect(
      store.acceptSetCookie(
        accountBRequest,
        'api_session=fixture-b; Path=/; Secure',
        now: now,
      ),
      isTrue,
    );
    expect(
      store.capture(ApiCookieIsolationStore.apiBase, now: now).cookieHeader,
      'api_session=fixture-b',
    );
  });

  test('logout invalidates captured requests and removes cookies', () {
    final store = ApiCookieIsolationStore()..activateSession('fixture-a');
    final captured = store.capture(login, now: now);
    expect(
      store.acceptSetCookie(
        captured,
        'api_session=fixture-a; Path=/; Secure',
        now: now,
      ),
      isTrue,
    );
    store.clearSession();
    expect(store.snapshot.accountId, isNull);
    expect(store.snapshot.cookieCount, 0);
    expect(
      store.acceptSetCookie(
        captured,
        'api_session=late-a; Path=/; Secure',
        now: now,
      ),
      isFalse,
    );
  });

  test('Max-Age zero deletes the matching cookie', () {
    final store = ApiCookieIsolationStore()..activateSession('fixture-a');
    var request = store.capture(login, now: now);
    expect(
      store.acceptSetCookie(
        request,
        'api_session=fixture-a; Path=/; Secure',
        now: now,
      ),
      isTrue,
    );
    request = store.capture(login, now: now);
    expect(
      store.acceptSetCookie(
        request,
        'api_session=deleted; Path=/; Secure; Max-Age=0',
        now: now,
      ),
      isTrue,
    );
    expect(store.capture(login, now: now).cookieHeader, isNull);
  });
}
