import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/data/network/article_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/network/service/wan_api_service.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_models.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_store.dart';
import 'package:wanandroid_flutter/src/data/network/session/web_cookie.dart';
import 'package:wanandroid_flutter/src/data/storage/session_storage.dart';
import 'package:wanandroid_flutter/src/model/user.dart';

void main() {
  test(
    'article, search and topic article reads carry the active session',
    () async {
      final SessionStore store = SessionStore(storage: _MemoryStorage());
      final SessionRequest login = await store.beginLogin();
      store.observeResponseCookies(login, <WebCookie>[
        WebCookie(
          name: 'JSESSIONID',
          value: 'active-session',
          domain: SessionStore.apiHost,
          path: '/',
          expiresAtMilliseconds: DateTime.now()
              .toUtc()
              .add(const Duration(days: 1))
              .millisecondsSinceEpoch,
          persistent: true,
        ),
      ]);
      expect(
        await store.commitLogin(
          login,
          const User(id: 7, username: 'fixture-user'),
        ),
        isTrue,
      );
      final _RecordingWanApiService service = _RecordingWanApiService();
      final DefaultArticleNetworkDataSource source =
          DefaultArticleNetworkDataSource(service, store);

      await source.articles(0, const LiveRequestCancellation());
      await source.search(0, 'flutter', const LiveRequestCancellation());
      await source.topicArticles(60, 0, const LiveRequestCancellation());

      expect(service.sessions, hasLength(3));
      for (final Object? value in service.sessions) {
        expect(value, isA<SessionRequest>());
        expect(
          store.cookieHeader(
            value! as SessionRequest,
            Uri.parse('https://wanandroid.com/'),
          ),
          contains('JSESSIONID=active-session'),
        );
      }
    },
  );
}

class _MemoryStorage implements SessionStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String? value) async {}
}

class _RecordingWanApiService implements WanApiService {
  final List<Object?> sessions = <Object?>[];

  Map<String, dynamic> _record(Object? session) {
    sessions.add(session);
    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> articles(
    int page,
    RequestCancellation cancellation, {
    Object? session,
  }) async => _record(session);

  @override
  Future<Map<String, dynamic>> questions(
    int page,
    RequestCancellation cancellation, {
    Object? session,
  }) async => _record(session);

  @override
  Future<Map<String, dynamic>> search(
    int page,
    String keyword,
    RequestCancellation cancellation, {
    Object? session,
  }) async => _record(session);

  @override
  Future<Map<String, dynamic>> topicArticles(
    int categoryId,
    int page,
    RequestCancellation cancellation, {
    Object? session,
  }) async => _record(session);

  @override
  Future<Map<String, dynamic>> hotKeys(
    RequestCancellation cancellation,
  ) async => <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> topics(RequestCancellation cancellation) async =>
      <String, dynamic>{};
}
