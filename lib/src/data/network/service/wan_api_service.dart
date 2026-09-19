import 'package:dio/dio.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';

abstract interface class WanApiService {
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

final class DioWanApiService implements WanApiService {
  DioWanApiService({Dio? dio}) : _dio = dio ?? createWanApiDio();

  final Dio _dio;

  @override
  Future<Map<String, dynamic>> articles(
    int page,
    RequestCancellation cancellation,
  ) => _get('article/list/$page/json', cancellation);

  @override
  Future<Map<String, dynamic>> questions(
    int page,
    RequestCancellation cancellation,
  ) => _get('wenda/list/$page/json', cancellation);

  @override
  Future<Map<String, dynamic>> hotKeys(RequestCancellation cancellation) =>
      _get('hotkey/json', cancellation);

  @override
  Future<Map<String, dynamic>> topics(RequestCancellation cancellation) =>
      _get('tree/json', cancellation);

  @override
  Future<Map<String, dynamic>> topicArticles(
    int categoryId,
    int page,
    RequestCancellation cancellation,
  ) => _request(
    (CancelToken token) => _dio.get<Object?>(
      'article/list/$page/json',
      queryParameters: <String, int>{'cid': categoryId},
      cancelToken: token,
    ),
    cancellation,
  );

  @override
  Future<Map<String, dynamic>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) => _request(
    (CancelToken token) => _dio.post<Object?>(
      'article/query/$page/json',
      data: <String, String>{'k': keyword},
      options: Options(contentType: Headers.formUrlEncodedContentType),
      cancelToken: token,
    ),
    cancellation,
  );

  Future<Map<String, dynamic>> _get(
    String path,
    RequestCancellation cancellation,
  ) => _request(
    (CancelToken token) => _dio.get<Object?>(path, cancelToken: token),
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
