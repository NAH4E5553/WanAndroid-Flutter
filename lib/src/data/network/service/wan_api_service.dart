import 'package:dio/dio.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';

abstract interface class WanApiService {
  Future<Map<String, dynamic>> articles(
    int page,
    RequestCancellation cancellation, {
    Object? session,
  });

  Future<Map<String, dynamic>> questions(
    int page,
    RequestCancellation cancellation, {
    Object? session,
  });

  Future<Map<String, dynamic>> search(
    int page,
    String keyword,
    RequestCancellation cancellation, {
    Object? session,
  });

  Future<Map<String, dynamic>> hotKeys(RequestCancellation cancellation);

  Future<Map<String, dynamic>> topics(RequestCancellation cancellation);

  Future<Map<String, dynamic>> topicArticles(
    int categoryId,
    int page,
    RequestCancellation cancellation, {
    Object? session,
  });
}

/// Session-bound endpoints; the session tag rides in `Options.extra` so the
/// interceptor can attach or withhold cookies per the frozen contract.
abstract interface class WanSessionApiService {
  Future<Map<String, dynamic>> login(
    String username,
    String password,
    Object? session,
  );

  Future<Map<String, dynamic>> userInfo(Object? session);

  Future<Map<String, dynamic>> logout(Object? session);

  Future<Map<String, dynamic>> collections(int page, Object? session);

  Future<Map<String, dynamic>> collectArticle(int articleId, Object? session);

  Future<Map<String, dynamic>> uncollectRecord(
    int recordId,
    int originId,
    Object? session,
  );

  Future<Map<String, dynamic>> uncollectArticleId(
    int articleId,
    Object? session,
  );
}

final class DioWanApiService implements WanApiService, WanSessionApiService {
  DioWanApiService({Dio? dio}) : _dio = dio ?? createWanApiDio();

  final Dio _dio;

  Map<String, Object?> _extra(Object? session) => session == null
      ? const <String, Object?>{}
      : <String, Object?>{'wan_session': session};

  @override
  Future<Map<String, dynamic>> articles(
    int page,
    RequestCancellation cancellation, {
    Object? session,
  }) => _get('article/list/$page/json', cancellation, session);

  @override
  Future<Map<String, dynamic>> questions(
    int page,
    RequestCancellation cancellation, {
    Object? session,
  }) => _get('wenda/list/$page/json', cancellation, session);

  @override
  Future<Map<String, dynamic>> hotKeys(RequestCancellation cancellation) =>
      _get('hotkey/json', cancellation, null);

  @override
  Future<Map<String, dynamic>> topics(RequestCancellation cancellation) =>
      _get('tree/json', cancellation, null);

  @override
  Future<Map<String, dynamic>> topicArticles(
    int categoryId,
    int page,
    RequestCancellation cancellation, {
    Object? session,
  }) => _request(
    (CancelToken token) => _dio.get<Object?>(
      'article/list/$page/json',
      queryParameters: <String, int>{'cid': categoryId},
      options: Options(extra: _extra(session)),
      cancelToken: token,
    ),
    cancellation,
  );

  @override
  Future<Map<String, dynamic>> search(
    int page,
    String keyword,
    RequestCancellation cancellation, {
    Object? session,
  }) => _request(
    (CancelToken token) => _dio.post<Object?>(
      'article/query/$page/json',
      data: <String, String>{'k': keyword},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: _extra(session),
      ),
      cancelToken: token,
    ),
    cancellation,
  );

  @override
  Future<Map<String, dynamic>> login(
    String username,
    String password,
    Object? session,
  ) => _request(
    (CancelToken token) => _dio.post<Object?>(
      'user/login',
      data: <String, String>{'username': username, 'password': password},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: _extra(session),
      ),
      cancelToken: token,
    ),
    const LiveRequestCancellation(),
  );

  @override
  Future<Map<String, dynamic>> userInfo(Object? session) =>
      _get('user/lg/userinfo/json', const LiveRequestCancellation(), session);

  @override
  Future<Map<String, dynamic>> logout(Object? session) =>
      _get('user/logout/json', const LiveRequestCancellation(), session);

  @override
  Future<Map<String, dynamic>> collections(int page, Object? session) => _get(
    'lg/collect/list/$page/json',
    const LiveRequestCancellation(),
    session,
  );

  @override
  Future<Map<String, dynamic>> collectArticle(int articleId, Object? session) =>
      _post('lg/collect/$articleId/json', session);

  @override
  Future<Map<String, dynamic>> uncollectRecord(
    int recordId,
    int originId,
    Object? session,
  ) => _post('lg/uncollect_originId/$recordId/json', session, originId);

  @override
  Future<Map<String, dynamic>> uncollectArticleId(
    int articleId,
    Object? session,
  ) => _post('lg/uncollect/$articleId/json', session);

  Future<Map<String, dynamic>> _post(
    String path,
    Object? session, [
    int? originId,
  ]) => _request(
    (CancelToken token) => _dio.post<Object?>(
      path,
      data: originId == null ? null : <String, int>{'originId': originId},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: _extra(session),
      ),
      cancelToken: token,
    ),
    const LiveRequestCancellation(),
  );

  Future<Map<String, dynamic>> _get(
    String path,
    RequestCancellation cancellation,
    Object? session,
  ) => _request(
    (CancelToken token) => _dio.get<Object?>(
      path,
      options: Options(extra: _extra(session)),
      cancelToken: token,
    ),
    cancellation,
  );

  Future<Map<String, dynamic>> _request(
    Future<Response<Object?>> Function(CancelToken token) send,
    RequestCancellation cancellation,
  ) async {
    cancellation.throwIfCancelled();
    final CancelToken token = CancelToken();
    final void Function() removeListener = cancellation.addCancelListener(() {
      if (!token.isCancelled) {
        token.cancel('request-cancelled');
      }
    });
    try {
      final Response<Object?> response = await send(token);
      cancellation.throwIfCancelled();
      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const NetworkResponseException();
      }
      return data;
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel || cancellation.isCancelled) {
        throw const RequestCancelledException();
      }
      throw NetworkRequestException(error.type.name);
    } finally {
      removeListener();
    }
  }
}

Dio createWanApiDio() => Dio(
  BaseOptions(
    baseUrl: 'https://wanandroid.com/',
    connectTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    followRedirects: false,
    maxRedirects: 0,
    validateStatus: (int? status) =>
        status != null && status >= 200 && status < 300,
    responseType: ResponseType.json,
  ),
);

final class NetworkRequestException implements Exception {
  const NetworkRequestException(this.reason);

  final String reason;
}

final class NetworkResponseException implements Exception {
  const NetworkResponseException();
}
