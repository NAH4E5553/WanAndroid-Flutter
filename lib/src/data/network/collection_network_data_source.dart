import 'package:wanandroid_flutter/src/data/network/service/wan_api_service.dart';

/// Raw collection endpoint access; callers own session tagging and envelope
/// decoding per the frozen contract.
abstract interface class CollectionNetworkDataSource {
  Future<Map<String, dynamic>> list(int page, Object? session);

  Future<Map<String, dynamic>> collect(int articleId, Object? session);

  Future<Map<String, dynamic>> uncollectArticle(int articleId, Object? session);

  Future<Map<String, dynamic>> uncollectRecord(
    int recordId,
    int originId,
    Object? session,
  );
}

final class DefaultCollectionNetworkDataSource
    implements CollectionNetworkDataSource {
  const DefaultCollectionNetworkDataSource(this._service);

  final WanSessionApiService _service;

  @override
  Future<Map<String, dynamic>> list(int page, Object? session) =>
      _service.collections(page, session);

  @override
  Future<Map<String, dynamic>> collect(int articleId, Object? session) =>
      _service.collectArticle(articleId, session);

  @override
  Future<Map<String, dynamic>> uncollectArticle(
    int articleId,
    Object? session,
  ) => _service.uncollectArticleId(articleId, session);

  @override
  Future<Map<String, dynamic>> uncollectRecord(
    int recordId,
    int originId,
    Object? session,
  ) => _service.uncollectRecord(recordId, originId, session);
}
