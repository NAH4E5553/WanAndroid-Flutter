import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/data/network/service/wan_api_service.dart';

abstract interface class ArticleNetworkDataSource {
  Future<Map<String, dynamic>> articles(
    int page,
    RequestCancellation cancellation,
  );

  Future<Map<String, dynamic>> questions(
    int page,
    RequestCancellation cancellation,
  );

  Future<Map<String, dynamic>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  );

  Future<Map<String, dynamic>> hotKeys(RequestCancellation cancellation);

  Future<Map<String, dynamic>> topics(RequestCancellation cancellation);

  Future<Map<String, dynamic>> topicArticles(
    int categoryId,
    int page,
    RequestCancellation cancellation,
  );
}

final class DefaultArticleNetworkDataSource
    implements ArticleNetworkDataSource {
  const DefaultArticleNetworkDataSource(this._service);

  final WanApiService _service;

  @override
  Future<Map<String, dynamic>> articles(
    int page,
    RequestCancellation cancellation,
  ) => _service.articles(page, cancellation);

  @override
  Future<Map<String, dynamic>> questions(
    int page,
    RequestCancellation cancellation,
  ) => _service.questions(page, cancellation);

  @override
  Future<Map<String, dynamic>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) => _service.search(page, keyword, cancellation);

  @override
  Future<Map<String, dynamic>> hotKeys(RequestCancellation cancellation) =>
      _service.hotKeys(cancellation);

  @override
  Future<Map<String, dynamic>> topics(RequestCancellation cancellation) =>
      _service.topics(cancellation);

  @override
  Future<Map<String, dynamic>> topicArticles(
    int categoryId,
    int page,
    RequestCancellation cancellation,
  ) => _service.topicArticles(categoryId, page, cancellation);
}
