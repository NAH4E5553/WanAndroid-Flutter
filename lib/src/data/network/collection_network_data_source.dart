import 'package:wanandroid_flutter/src/data/network/service/wan_api_service.dart';

/// 直接访问收藏端点；调用方负责会话打标与 envelope 解码，
/// 遵循已冻结的契约。
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
