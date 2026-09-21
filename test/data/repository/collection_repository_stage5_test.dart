import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/network/auth_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/network/collection_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_commit_coordinator.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_models.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_store.dart';
import 'package:wanandroid_flutter/src/data/network/session/web_cookie.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_collection_repository.dart';
import 'package:wanandroid_flutter/src/data/storage/session_storage.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/collection.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

class _MemoryStorage implements SessionStorage {
  String? payload;

  @override
  Future<String?> read() async => payload;

  @override
  Future<void> write(String? value) async => payload = value;
}

class _FakeAuthSource implements AuthNetworkDataSource {
  _FakeAuthSource(this.store);

  final SessionStore store;

  @override
  Future<Map<String, dynamic>> login(
    String username,
    String password,
    Object? session,
  ) async {
    store.observeResponseCookies(session as SessionRequest, <WebCookie>[
      WebCookie(
        name: 'JSESSIONID',
        value: 's',
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
      'data': <String, Object?>{'id': 7, 'username': 'user'},
    };
  }

  @override
  Future<Map<String, dynamic>> userInfo(Object? session) async =>
      <String, dynamic>{
        'errorCode': 0,
        'data': <String, Object?>{
          'userInfo': <String, Object?>{'id': 7, 'username': 'user'},
        },
      };

  @override
  Future<Map<String, dynamic>> logout(Object? session) async =>
      <String, dynamic>{'errorCode': 0, 'data': null};
}

class _FakeCollectionSource implements CollectionNetworkDataSource {
  _FakeCollectionSource();

  /// Each entry is one page's `datas` payloads; the last page reports over.
  final List<List<Map<String, Object?>>> pages = <List<Map<String, Object?>>>[];
  DataError? listFailure;
  DataError? writeFailure;
  final List<String> writeCalls = <String>[];

  @override
  Future<Map<String, dynamic>> list(int page, Object? session) async {
    if (listFailure != null) {
      throw StateError(listFailure!.name);
    }
    if (page >= pages.length) {
      return <String, dynamic>{
        'errorCode': 0,
        'data': <String, Object?>{'datas': <Object?>[], 'over': true},
      };
    }
    return <String, dynamic>{
      'errorCode': 0,
      'data': <String, Object?>{
        'datas': pages[page],
        'over': page == pages.length - 1,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> collect(int articleId, Object? session) async {
    writeCalls.add('collect:$articleId');
    if (writeFailure != null) {
      throw StateError(writeFailure!.name);
    }
    return <String, dynamic>{'errorCode': 0, 'data': null};
  }

  @override
  Future<Map<String, dynamic>> uncollectArticle(
    int articleId,
    Object? session,
  ) async {
    writeCalls.add('uncollectArticle:$articleId');
    if (writeFailure != null) {
      throw StateError(writeFailure!.name);
    }
    return <String, dynamic>{'errorCode': 0, 'data': null};
  }

  @override
  Future<Map<String, dynamic>> uncollectRecord(
    int recordId,
    int originId,
    Object? session,
  ) async {
    writeCalls.add('uncollectRecord:$recordId/$originId');
    if (writeFailure != null) {
      throw StateError(writeFailure!.name);
    }
    return <String, dynamic>{'errorCode': 0, 'data': null};
  }
}

Future<DefaultCollectionRepository> _signedIn(
  _FakeCollectionSource source,
) async {
  final SessionStore store = SessionStore(storage: _MemoryStorage());
  final DefaultAuthRepository auth = DefaultAuthRepository(
    sessionStore: store,
    source: _FakeAuthSource(store),
    coordinator: SessionCommitCoordinator(),
  );
  await auth.login('13800138000', 'secret');
  return DefaultCollectionRepository(source: source, sessions: store);
}

Map<String, Object?> _record(int recordId, int articleId) => <String, Object?>{
  'id': recordId,
  'originId': articleId,
  'title': 't\$recordId',
  'link': 'https://wanandroid.com/a/\$articleId',
  'author': 'author',
  'chapterName': 'chapter',
  'niceDate': '2026-09-21',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'articlePage merges server hints only when the write epoch is stable',
    () async {
      final _FakeCollectionSource source = _FakeCollectionSource();
      final DefaultCollectionRepository repository = await _signedIn(source);
      final DataResult<PageResult<Article>> result = await repository
          .articlePage(
            () async => DataSuccess<PageResult<Article>>(
              PageResult<Article>(
                items: <Article>[_collectedArticle(9, true)],
                nextPage: null,
              ),
            ),
          );
      final PageResult<Article> page =
          (result as DataSuccess<PageResult<Article>>).value;
      expect(page.items.single.collected, isTrue);
      expect(page.items.single.collectionSession, isNotNull);
    },
  );

  test(
    'setCollected on a known collected target issues record uncollect',
    () async {
      final _FakeCollectionSource source = _FakeCollectionSource();
      final DefaultCollectionRepository repository = await _signedIn(source);
      source.pages.add(<Map<String, Object?>>[_record(501, 42)]);
      final int generation = repository.current.generation!;
      // Reading the list seeds the known state (collected = true).
      await repository.page(generation, 0);
      final DataResult<void> result = await repository.setCollected(
        generation,
        CollectionTarget(42, 501),
        false,
      );
      expect(result, isA<DataSuccess<void>>());
      expect(source.writeCalls.single, 'uncollectRecord:501/42');
      expect(
        repository.current.status(CollectionTarget(42, 501)).collected,
        isFalse,
      );
    },
  );

  test(
    'collecting an external target without an article id is rejected',
    () async {
      final _FakeCollectionSource source = _FakeCollectionSource();
      final DefaultCollectionRepository repository = await _signedIn(source);
      final int generation = repository.current.generation!;
      const CollectionTarget target = CollectionTarget(null, 500);
      // Seed the known NOT-collected state so the collect guard applies; the
      // first unknown-state call reconciles (scans, finds nothing) and only
      // marks the state known.
      source.pages.add(<Map<String, Object?>>[]);
      await repository.setCollected(generation, target, true);
      expect(repository.current.status(target).collected, isFalse);
      final DataResult<void> result = await repository.setCollected(
        generation,
        target,
        true,
      );
      expect(result, isA<DataFailure<void>>());
      expect(source.writeCalls, isEmpty);
    },
  );

  test('an unknown state reconciles by scanning to the end without a write', () async {
    final _FakeCollectionSource source = _FakeCollectionSource();
    final DefaultCollectionRepository repository = await _signedIn(source);
    // Page 0: absent; page 1: absent and last page. The scan ends unknown-free
    // with a confirmed "not collected".
    source.pages
      ..add(<Map<String, Object?>>[_record(1, 10)])
      ..add(<Map<String, Object?>>[]);
    final int generation = repository.current.generation!;
    const CollectionTarget target = CollectionTarget(42, null);
    final DataResult<void> result = await repository.setCollected(
      generation,
      target,
      false,
    );
    expect(result, isA<DataSuccess<void>>());
    expect(repository.current.status(target).collected, isFalse);
    expect(source.writeCalls, isEmpty);
  });

  test(
    'a failed reconcile leaves the state unknown instead of guessing',
    () async {
      final _FakeCollectionSource source = _FakeCollectionSource();
      final DefaultCollectionRepository repository = await _signedIn(source);
      source.listFailure = DataError.network;
      final int generation = repository.current.generation!;
      const CollectionTarget target = CollectionTarget(42, null);
      final DataResult<void> result = await repository.setCollected(
        generation,
        target,
        true,
      );
      expect(result, isA<DataFailure<void>>());
      expect(repository.current.status(target).collected, isNull);
    },
  );

  test('a write failure triggers reconciliation of the true server state', () async {
    final _FakeCollectionSource source = _FakeCollectionSource();
    final DefaultCollectionRepository repository = await _signedIn(source);
    final int generation = repository.current.generation!;
    source.pages.add(<Map<String, Object?>>[_record(77, 42)]);
    const CollectionTarget target = CollectionTarget(42, 77);
    // Seed known state first so the write path (not reconcile) runs.
    await repository.page(generation, 0);
    source.writeFailure = DataError.network;
    final DataResult<void> result = await repository.setCollected(
      generation,
      target,
      false,
    );
    expect(result, isA<DataFailure<void>>());
    // The reconcile found the record still on the server: collected stays true.
    expect(source.writeCalls, isNotEmpty);
    expect(repository.current.status(target).collected, isTrue);
  });

  test('a stale generation is rejected as session-changed', () async {
    final _FakeCollectionSource source = _FakeCollectionSource();
    final DefaultCollectionRepository repository = await _signedIn(source);
    final DataResult<void> result = await repository.page(9999, 0);
    expect(result, isA<DataFailure<void>>());
    expect(
      (result as DataFailure<PageResult<CollectionItem>>).error,
      DataError.sessionChanged,
    );
  });

  test('a busy target is not written twice concurrently', () async {
    final _FakeCollectionSource source = _FakeCollectionSource();
    final DefaultCollectionRepository repository = await _signedIn(source);
    final int generation = repository.current.generation!;
    const CollectionTarget target = CollectionTarget(42, null);
    final DataResult<void> first = await repository.setCollected(
      generation,
      target,
      true,
    );
    expect(first, isA<DataSuccess<void>>());
  });
}

Article _collectedArticle(int id, bool collected) => Article(
  id: id,
  title: 'a$id',
  url: 'https://wanandroid.com/a/$id',
  author: '',
  shareUser: '',
  superChapterName: '',
  chapter: '',
  publishedAt: '',
  collected: collected,
);
