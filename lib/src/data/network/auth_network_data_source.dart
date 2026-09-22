import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/data/network/service/wan_api_service.dart';

/// Raw session-bound endpoint access; callers own session tagging and Wan
/// envelope decoding via [requestWithData].
abstract interface class AuthNetworkDataSource {
  Future<Map<String, dynamic>> login(
    String username,
    String password,
    Object? session,
    RequestCancellation cancellation,
  );

  Future<Map<String, dynamic>> userInfo(Object? session);

  Future<Map<String, dynamic>> logout(Object? session);
}

final class DefaultAuthNetworkDataSource implements AuthNetworkDataSource {
  const DefaultAuthNetworkDataSource(this._service);

  final WanSessionApiService _service;

  @override
  Future<Map<String, dynamic>> login(
    String username,
    String password,
    Object? session,
    RequestCancellation cancellation,
  ) => _service.login(username, password, session, cancellation);

  @override
  Future<Map<String, dynamic>> userInfo(Object? session) =>
      _service.userInfo(session);

  @override
  Future<Map<String, dynamic>> logout(Object? session) =>
      _service.logout(session);
}

class UserEnvelope {
  const UserEnvelope({
    required this.id,
    required this.username,
    required this.nickname,
    required this.cookies,
  });

  final int id;
  final String username;
  final String? nickname;
  final List<String> cookies;
}

/// Login `data` is the user object itself; the session cookie arrives via
/// Set-Cookie headers and is captured by the session interceptor.
UserEnvelope parseLoginResponse(Map<String, dynamic> body) {
  final Object? data = body['data'];
  if (data is! Map) {
    throw const FormatException();
  }
  return parseUserEnvelope(data);
}

UserEnvelope parseUserInfo(Object? data) {
  if (data is! Map) {
    throw const FormatException();
  }
  final Object? userInfo = data['userInfo'];
  if (userInfo is! Map) {
    throw const FormatException();
  }
  return parseUserEnvelope(userInfo);
}

UserEnvelope parseUserEnvelope(Map<Object?, Object?> data) {
  final Object? id = data['id'];
  final Object? username = data['username'];
  final Object? nickname = data['nickname'];
  final Object? cookies = data['cookies'];
  if (id is! int || username is! String) {
    throw const FormatException();
  }
  return UserEnvelope(
    id: id,
    username: username,
    nickname: nickname is String ? nickname : null,
    cookies: cookies is List
        ? cookies.whereType<String>().toList()
        : const <String>[],
  );
}
