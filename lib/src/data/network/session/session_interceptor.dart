import 'dart:async';

import 'package:dio/dio.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_commit_coordinator.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_models.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_store.dart';
import 'package:wanandroid_flutter/src/data/network/session/web_cookie.dart';

/// 把捕获到的会话 Cookie 附加到 API 请求上，并观察响应中的
/// Set-Cookie 值。每个请求的标签通过 `Options.extra['wan_session']`
/// 传递；未打标签的请求不携带 Cookie。
final class SessionInterceptor extends Interceptor {
  const SessionInterceptor(this._store, this._coordinator);

  final SessionStore _store;
  final SessionCommitCoordinator _coordinator;

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
    _processResponse(
      response.requestOptions,
      response.headers,
      sessionExpired: _hasExpiredEnvelope(response.data),
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _processResponse(
      err.requestOptions,
      err.response?.headers,
      sessionExpired:
          err.response?.statusCode == 401 ||
          _hasExpiredEnvelope(err.response?.data),
    );
    handler.next(err);
  }

  void _processResponse(
    RequestOptions options,
    Headers? headers, {
    required bool sessionExpired,
  }) {
    final Object? tag = options.extra[sessionExtraKey];
    if (tag is! SessionRequest || tag.mode == SessionRequestMode.logout) {
      return;
    }
    if (tag.mode == SessionRequestMode.login) {
      _capture(tag, headers);
      return;
    }
    unawaited(
      _coordinator
          .run<void>(() async {
            if (sessionExpired) {
              await _store.expire(tag);
              return;
            }
            _capture(tag, headers);
            await _store.flushResponseCookies(tag);
          })
          .catchError((Object _) {
            // SessionStore 已通过其权威快照发布过存储失败；
            // 响应投递不得二次失败。
          }),
    );
  }

  void _capture(SessionRequest tag, Headers? headers) {
    if (headers == null) {
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

  bool _hasExpiredEnvelope(Object? data) =>
      data is Map && data['errorCode'] == -1001;
}
