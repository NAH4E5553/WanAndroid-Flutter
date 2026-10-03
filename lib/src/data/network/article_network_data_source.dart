import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/data/network/service/wan_api_service.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_store.dart';

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

/// 为每个公开读取请求打上捕获到的会话标签，使拦截器能在会话激活时
/// 附加 Cookie；访客请求则不携带 Cookie。
final class DefaultArticleNetworkDataSource
    implements ArticleNetworkDataSource {
  DefaultArticleNetworkDataSource(this._service, this._sessions);

  final WanApiService _service;
  final SessionStore _sessions;

  Object _sessionTag() => _sessions.capture();

  @override
  Future<Map<String, dynamic>> articles(
    int page,
    RequestCancellation cancellation,
  ) => _service.articles(page, cancellation, session: _sessionTag());

  @override
  Future<Map<String, dynamic>> questions(
    int page,
    RequestCancellation cancellation,
  ) => _service.questions(page, cancellation, session: _sessionTag());

  @override
  Future<Map<String, dynamic>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) => _service.search(page, keyword, cancellation, session: _sessionTag());

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
  ) => _service.topicArticles(
    categoryId,
    page,
    cancellation,
    session: _sessionTag(),
  );
}
