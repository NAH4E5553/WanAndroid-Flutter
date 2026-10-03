import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_models.dart';
import 'package:wanandroid_flutter/src/data/network/session/web_cookie.dart';
import 'package:wanandroid_flutter/src/data/storage/session_storage.dart';
import 'package:wanandroid_flutter/src/model/user.dart';

class SessionStorageException implements Exception {
  const SessionStorageException();
}

class SessionChangedException implements Exception {
  const SessionChangedException();
}

/// 会话 Cookie 与各阶段状态的唯一权威。所有内存/磁盘
/// 状态迁移都经由本类完成；Dart 的单线程事件循环使每个异步
/// 方法体在 await 之间保持原子性。
class SessionStore extends ChangeNotifier {
  SessionStore({required this._storage});

  static const String apiHost = 'wanandroid.com';
  static const int _maxPayloadLength = 65536;
  static const int _maxCookies = 32;

  final SessionStorage _storage;
  final String instanceKey = DateTime.now().microsecondsSinceEpoch
      .toRadixString(36);

  SessionSnapshot _snapshot = const SessionSnapshot();
  List<WebCookie> _cookies = const <WebCookie>[];
  bool _initialized = false;

  SessionSnapshot get snapshot => _snapshot;
  int get generation => _snapshot.generation;

  String? authenticatedVersionKey() =>
      _snapshot.authenticatedVersionKey(instanceKey);

  bool isCurrent(SessionRequest request) =>
      request.generation == _snapshot.generation;

  static bool isApiUrl(Uri url) =>
      url.scheme == 'https' && url.host == apiHost && url.port == 443;

  Future<SessionSnapshot> initialize() async {
    if (_initialized) {
      return _snapshot;
    }
    _initialized = true;
    final String? payload;
    try {
      payload = await _storage.read();
    } on Object {
      await _clearLocked(SessionNotice.storageError);
      return _snapshot;
    }
    if (payload == null) {
      _snapshot = const SessionSnapshot(phase: SessionPhase.guest);
      notifyListeners();
      return _snapshot;
    }
    if (payload.length > _maxPayloadLength) {
      await _clearLocked(SessionNotice.storageError);
      return _snapshot;
    }
    final decoded = SecureSessionStorageAdapter.decode(payload);
    final User? user = decoded == null ? null : _parseUser(decoded.user);
    if (user == null) {
      await _clearLocked(SessionNotice.storageError);
      return _snapshot;
    }
    final List<WebCookie> cookies = decoded!.cookies
        .map(WebCookie.fromJson)
        .whereType<WebCookie>()
        .where((WebCookie cookie) => _acceptable(cookie) && cookie.persistent)
        .toList(growable: false);
    if (cookies.isEmpty) {
      await _clearLocked(SessionNotice.expired);
      return _snapshot;
    }
    if (cookies.length > _maxCookies) {
      await _clearLocked(SessionNotice.storageError);
      return _snapshot;
    }
    _cookies = cookies;
    _snapshot = const SessionSnapshot(phase: SessionPhase.verifying)
        .copyWith(user: user);
    notifyListeners();
    return _snapshot;
  }

  /// 捕获是同步的：初始化与过期在此之前已由 [initialize]
  /// 和服务端 -1001 处理完毕。
  SessionRequest capture() => SessionRequest.normal(_snapshot.generation);

  /// 在登录尝试前清除当前账号。存储失败会使这次状态迁移无法上报，
  /// 必须中止登录。
  Future<SessionRequest> beginLogin() async {
    final bool cleared = await _clearLocked(SessionNotice.none);
    if (!cleared) {
      throw const SessionStorageException();
    }
    return SessionRequest.login(_snapshot.generation);
  }

  /// 分离当前账号的 Cookie，以尽力完成服务端登出；
  /// 返回的身份属于分离之后的访客状态。
  Future<SessionRequest> detach() async {
    final List<WebCookie> old = _cookies;
    final bool cleared = await _clearLocked(SessionNotice.none);
    if (!cleared) {
      throw const SessionStorageException();
    }
    return SessionRequest.detachedLogout(_snapshot.generation, old);
  }

  /// 单个请求的 Cookie 头；登录请求不携带任何 Cookie，
  /// 分离登出只携带被分离账号的 Cookie。
  String cookieHeader(SessionRequest request, Uri url) {
    if (!isApiUrl(url)) {
      return '';
    }
    final List<WebCookie> selected = switch (request.mode) {
      SessionRequestMode.login => const <WebCookie>[],
      SessionRequestMode.logout => request.logoutCookies,
      SessionRequestMode.normal =>
        isCurrent(request) ? _cookies : throw const SessionChangedException(),
    };
    return selected
        .where((WebCookie cookie) => _acceptable(cookie) && !cookie.expired)
        .map((WebCookie cookie) => cookie.toHeader())
        .join('; ');
  }

  Future<bool> commitLogin(
    SessionRequest request,
    User user, {
    RequestCancellation cancellation = const LiveRequestCancellation(),
  }) async {
    cancellation.throwIfCancelled();
    if (!isCurrent(request)) {
      return false;
    }
    final List<WebCookie> received =
        _pendingResponseCookies.remove(request) ?? const <WebCookie>[];
    if (!_validUser(user)) {
      await _clearLocked(SessionNotice.none);
      return false;
    }
    return _persistAuthenticated(
      request,
      user,
      received,
      cancellation: cancellation,
    );
  }

  /// 把已验证的身份附加到已恢复的会话上；绝不允许把不同的账号
  /// 附加到已恢复的 Cookie 上。
  Future<bool> verified(SessionRequest request, User user) async {
    if (!isCurrent(request) || _snapshot.user == null) {
      return false;
    }
    if (!_validUser(user) || user.id != _snapshot.user?.id) {
      await _clear(SessionNotice.expired);
      return false;
    }
    return _persistAuthenticated(request, user, _cookies);
  }

  void verificationFailed(SessionRequest request) {
    if (isCurrent(request) && _snapshot.user != null) {
      _snapshot = _snapshot.copyWith(phase: SessionPhase.unverified);
      notifyListeners();
    }
  }

  Future<void> expire(SessionRequest request) async {
    if (isCurrent(request) && _snapshot.user != null) {
      await _clear(SessionNotice.expired);
    }
  }

  Future<void> abortLogin(SessionRequest request) async {
    _pendingResponseCookies.remove(request);
    if (isCurrent(request)) {
      await _clear(SessionNotice.none);
    }
  }

  /// 把在已打标响应上观察到的 Set-Cookie 值加入队列；在下次对该请求
  /// 调用 [flushResponseCookies] 时应用。
  void observeResponseCookies(SessionRequest request, List<WebCookie> cookies) {
    if (cookies.isEmpty ||
        request.mode == SessionRequestMode.logout ||
        !isCurrent(request)) {
      return;
    }
    final List<WebCookie> merged = List<WebCookie>.of(
      _pendingResponseCookies[request] ?? const <WebCookie>[],
    );
    merged.addAll(cookies);
    _pendingResponseCookies[request] = merged;
  }

  Future<void> flushResponseCookies(SessionRequest request) async {
    final List<WebCookie> received =
        _pendingResponseCookies.remove(request) ?? const <WebCookie>[];
    if (received.isEmpty || !isCurrent(request) || _snapshot.user == null) {
      return;
    }
    final Map<(String, String, String), WebCookie> next =
        <(String, String, String), WebCookie>{
          for (final WebCookie cookie in _cookies)
            (cookie.name, cookie.domain, cookie.path): cookie,
        };
    for (final WebCookie cookie in received.where(_acceptable)) {
      final (String, String, String) key = (
        cookie.name,
        cookie.domain,
        cookie.path,
      );
      if (cookie.expired) {
        next.remove(key);
      } else {
        next[key] = cookie;
      }
    }
    final List<WebCookie> valid = next.values
        .where((WebCookie cookie) => !cookie.expired)
        .toList(growable: false);
    if (valid.isEmpty) {
      await _clear(SessionNotice.expired);
      return;
    }
    if (valid.length > _maxCookies) {
      await _clear(SessionNotice.storageError);
      return;
    }
    await _persist(_snapshot.user!, valid);
    _cookies = valid;
  }

  final Map<SessionRequest, List<WebCookie>> _pendingResponseCookies =
      <SessionRequest, List<WebCookie>>{};

  Future<bool> _persistAuthenticated(
    SessionRequest request,
    User user,
    List<WebCookie> received, {
    RequestCancellation cancellation = const LiveRequestCancellation(),
  }) async {
    final Map<(String, String, String), WebCookie> next =
        <(String, String, String), WebCookie>{};
    for (final WebCookie cookie in received) {
      if (!_acceptable(cookie) || cookie.expired) {
        continue;
      }
      next[(cookie.name, cookie.domain, cookie.path)] = cookie;
      if (next.length > _maxCookies) {
        await _clearLocked(SessionNotice.storageError);
        return false;
      }
    }
    if (next.isEmpty) {
      await _clearLocked(SessionNotice.expired);
      return false;
    }
    final List<WebCookie> cookies = next.values.toList(growable: false);
    try {
      await _persist(user, cookies);
    } on Object {
      throw const SessionStorageException();
    }
    if (cancellation.isCancelled) {
      // 路由可能在安全存储写入进行中时离开。这种情况下绝不能发布
      // 刚持久化的身份，哪怕是短暂发布也不行。
      await _clearLocked(SessionNotice.none);
      throw const RequestCancelledException();
    }
    _cookies = cookies;
    _snapshot = SessionSnapshot(
      phase: SessionPhase.authenticated,
      user: user,
      generation: request.generation,
    );
    notifyListeners();
    return true;
  }

  Future<void> _persist(User user, List<WebCookie> cookies) async {
    final List<WebCookie> persistent = cookies
        .where((WebCookie cookie) => cookie.persistent && !cookie.expired)
        .toList(growable: false);
    // 仅会话期有效的 Cookie 只留在内存中，重启后绝不保留。
    final String? payload = persistent.isEmpty
        ? null
        : jsonEncode(<String, Object?>{
            'user': <String, Object?>{
              'id': user.id,
              'username': user.username,
              'nickname': user.nickname,
            },
            'cookies': persistent.map((WebCookie c) => c.toJson()).toList(),
          });
    if (payload != null && payload.length > _maxPayloadLength) {
      await _clearLocked(SessionNotice.storageError);
      throw const SessionStorageException();
    }
    try {
      await _storage.write(payload);
    } on Object {
      await _clearLocked(SessionNotice.storageError);
      throw const SessionStorageException();
    }
  }

  /// 立即标记内存中的访客状态；存储清理失败会以
  /// [SessionNotice.storageError] 的形式暴露，因为过期负载已无法移除。
  Future<void> _clear(SessionNotice notice) async {
    await _clearLocked(notice);
  }

  Future<bool> _clearLocked(SessionNotice notice) async {
    _cookies = const <WebCookie>[];
    _pendingResponseCookies.clear();
    bool success = true;
    try {
      await _storage.write(null);
    } on Object {
      success = false;
    }
    _snapshot = SessionSnapshot(
      phase: SessionPhase.guest,
      generation: _snapshot.generation + 1,
      notice: success ? notice : SessionNotice.storageError,
    );
    notifyListeners();
    return success;
  }

  bool _acceptable(WebCookie cookie) =>
      cookie.domain == apiHost && cookie.name.isNotEmpty;

  static bool _validUser(User user) =>
      user.id > 0 &&
      user.username.trim().isNotEmpty &&
      user.username.length <= 200 &&
      (user.nickname ?? '').length <= 200;

  static User? _parseUser(Map<String, Object?> json) {
    final Object? id = json['id'];
    final Object? username = json['username'];
    final Object? nickname = json['nickname'];
    if (id is! int || username is! String) {
      return null;
    }
    final User user = User(
      id: id,
      username: username,
      nickname: nickname is String ? nickname : null,
    );
    return _validUser(user) ? user : null;
  }
}

/// 单独拆分出来，使测试无需插件即可复用负载编解码器。
class SecureSessionStorageAdapter {
  const SecureSessionStorageAdapter._();

  static String encode(User user, List<WebCookie> cookies) =>
      jsonEncode(<String, Object?>{
        'user': <String, Object?>{
          'id': user.id,
          'username': user.username,
          'nickname': user.nickname,
        },
        'cookies': cookies.map((WebCookie c) => c.toJson()).toList(),
      });

  static ({Map<String, Object?> user, List<Object?> cookies})? decode(
    String payload,
  ) {
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }
    final Object? user = decoded['user'];
    final Object? cookies = decoded['cookies'];
    if (user is! Map || cookies is! List) {
      return null;
    }
    return (user: Map<String, Object?>.from(user), cookies: cookies);
  }
}
