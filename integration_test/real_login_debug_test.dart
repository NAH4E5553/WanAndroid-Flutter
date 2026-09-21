import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/network/auth_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/network/collection_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/network/service/wan_api_service.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_commit_coordinator.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_interceptor.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_store.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_collection_repository.dart';
import 'package:wanandroid_flutter/src/data/storage/session_storage.dart';
import 'package:wanandroid_flutter/src/model/collection.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

/// REAL-ACCOUNT DEBUG HARNESS — run manually only, never in CI.
///
/// Credentials come from the environment at invocation time and are never
/// written into the repository:
///   flutter test integration_test/real_login_debug_test.dart \
///     --dart-define=RUN_REAL_LOGIN_DEBUG=true \
///     --dart-define=DEBUG_USER=... --dart-define=DEBUG_PASS=...
///
/// Records: real-account acceptance is documented separately from Fake
/// automation per the project boundary.
void main() {
  test('real login debug (manual opt-in)', () async {
    const bool enabled = bool.fromEnvironment('RUN_REAL_LOGIN_DEBUG');
    const String user = String.fromEnvironment('DEBUG_USER');
    const String pass = String.fromEnvironment('DEBUG_PASS');
    if (!enabled || user.isEmpty || pass.isEmpty) {
      markTestSkipped(
        'real login debug requires RUN_REAL_LOGIN_DEBUG=true and '
        'DEBUG_USER/DEBUG_PASS dart-defines',
      );
      return;
    }
    final SessionStore store = SessionStore(storage: _MemoryStorage());
    final Dio dio = createWanApiDio()
      ..interceptors.add(SessionInterceptor(store));
    final DefaultAuthRepository auth = DefaultAuthRepository(
      sessionStore: store,
      source: DefaultAuthNetworkDataSource(DioWanApiService(dio: dio)),
      coordinator: SessionCommitCoordinator(),
    );
    final DefaultCollectionRepository collections = DefaultCollectionRepository(
      source: DefaultCollectionNetworkDataSource(DioWanApiService(dio: dio)),
      sessions: store,
    );

    final DataResult<void> result = await auth.login(user, pass);
    // ignore: avoid_print
    print('[real-login] result=$result');
    // ignore: avoid_print
    print(
      '[real-login] phase=${store.snapshot.phase} '
      'user=${store.snapshot.user?.displayName}',
    );
    expect(result, isA<DataSuccess<void>>());
    expect(store.snapshot.authenticated, isTrue);

    // Authenticated read through the attached session cookie.
    final int generation = store.snapshot.generation;
    final DataResult<PageResult<CollectionItem>> page = await collections.page(
      generation,
      0,
    );
    final int collectionCount = page is DataSuccess<PageResult<CollectionItem>>
        ? page.value.items.length
        : -1;
    // ignore: avoid_print
    print('[real-login] collections=$collectionCount');
  });
}

class _MemoryStorage implements SessionStorage {
  String? payload;

  @override
  Future<String?> read() async => payload;

  @override
  Future<void> write(String? value) async => payload = value;
}
