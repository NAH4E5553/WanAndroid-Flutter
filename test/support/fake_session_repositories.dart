import 'package:flutter/foundation.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/collection_repository.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/collection.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

/// Guest-state auth fake for widget/integration fixtures.
class FakeAuthRepository extends ChangeNotifier implements AuthRepository {
  @override
  AuthStateView view() => AuthStateView(
    loading: false,
    authenticated: false,
    unverified: false,
    expiredNotice: false,
    storageNotice: false,
    displayName: null,
  );

  @override
  Future<DataResult<void>> login(
    String username,
    String password, {
    RequestCancellation cancellation = const LiveRequestCancellation(),
  }) async => const DataSuccess<void>(null);

  @override
  Future<LogoutOutcome> logout() async =>
      LogoutOutcome(generation: 1, remote: const DataSuccess<void>(null));

  @override
  Future<DataResult<void>> restore() async => const DataSuccess<void>(null);
}

/// Empty guest collection fake.
class FakeCollectionRepository extends ChangeNotifier
    implements CollectionRepository {
  @override
  CollectionSnapshot get current => const CollectionSnapshot();

  @override
  Future<DataResult<PageResult<Article>>> articlePage(
    Future<DataResult<PageResult<Article>>> Function() load,
  ) => load();

  @override
  Future<DataResult<PageResult<CollectionItem>>> page(
    int generation,
    int page,
  ) async =>
      const DataFailure<PageResult<CollectionItem>>(DataError.sessionChanged);

  @override
  Future<DataResult<void>> reconcile(
    int generation,
    CollectionTarget target,
  ) async => const DataSuccess<void>(null);

  @override
  Future<DataResult<void>> setCollected(
    int generation,
    CollectionTarget target,
    bool collected,
  ) async => const DataSuccess<void>(null);
}
