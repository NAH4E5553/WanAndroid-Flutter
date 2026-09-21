import 'package:dio/dio.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_models.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_store.dart';
import 'package:wanandroid_flutter/src/data/network/session/web_cookie.dart';

/// Attaches the captured session's cookies to API requests and observes
/// Set-Cookie values on responses. The per-request tag travels in
/// `Options.extra['wan_session']`; requests without a tag stay cookie-free.
final class SessionInterceptor extends Interceptor {
  const SessionInterceptor(this._store);

  final SessionStore _store;

  static const String sessionExtraKey = 'wan_session';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final Object? tag = options.extra[sessionExtraKey];
    if (tag is SessionRequest) {
      try {
        final String header = _store.cookieHeader(tag, options.uri);
        if (header.isNotEmpty) {
          options.headers['Cookie'] = header;
        }
      } on SessionChangedException {
        handler.reject(
          DioException(
            requestOptions: options,
            error: const SessionChangedException(),
          ),
        );
        return;
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    _capture(response.requestOptions, response.headers);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _capture(err.requestOptions, err.response?.headers);
    handler.next(err);
  }

  void _capture(RequestOptions options, Headers? headers) {
    final Object? tag = options.extra[sessionExtraKey];
    if (tag is! SessionRequest || headers == null) {
      return;
    }
    final List<WebCookie> cookies = (headers['set-cookie'] ?? const <String>[])
        .map(
          (String value) =>
              WebCookie.parse(value, apiHost: SessionStore.apiHost),
        )
        .nonNulls
        .toList(growable: false);
    if (cookies.isNotEmpty) {
      _store.observeResponseCookies(tag, cookies);
    }
  }
}
