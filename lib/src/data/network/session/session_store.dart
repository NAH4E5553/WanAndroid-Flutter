import 'dart:convert';

import 'package:flutter/foundation.dart';
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

/// Single authority for session cookies and phases. All memory/disk
/// transitions run through this class; Dart's single-threaded event loop makes
/// each async method body atomic between awaits.
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

  /// Capture is synchronous: initialization and expiry are handled by
  /// [initialize] and server-side -1001 handling beforehand.
  SessionRequest capture() => SessionRequest.normal(_snapshot.generation);

  /// Clears the current account before a login attempt. Storage failure makes
  /// the transition unreportable and must abort the login.
  Future<SessionRequest> beginLogin() async {
    final bool cleared = await _clearLocked(SessionNotice.none);
    if (!cleared) {
      throw const SessionStorageException();
    }
    return SessionRequest.login(_snapshot.generation);
  }

  /// Detaches the current account's cookies for a best-effort server logout;
  /// the returned identity belongs to the post-detach guest state.
  Future<SessionRequest> detach() async {
    final List<WebCookie> old = _cookies;
    final bool cleared = await _clearLocked(SessionNotice.none);
    if (!cleared) {
      throw const SessionStorageException();
    }
    return SessionRequest.detachedLogout(_snapshot.generation, old);
  }

  /// Cookie header for one request; login requests carry no cookies and
  /// detached logouts carry only the detached account's cookies.
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

  Future<bool> commitLogin(SessionRequest request, User user) async {
    if (!isCurrent(request)) {
      return false;
    }
    final List<WebCookie> received =
        _pendingResponseCookies.remove(request) ?? const <WebCookie>[];
    if (!_validUser(user)) {
      await _clearLocked(SessionNotice.none);
      return false;
    }
    return _persistAuthenticated(request, user, received);
  }

  /// Attaches a verified identity to a restored session; a different account
  /// must never be attached to restored cookies.
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

  /// Queues Set-Cookie values observed on a tagged response; applied on the
  /// next [flushResponseCookies] for that request.
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
    List<WebCookie> received,
  ) async {
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
    // Session-only cookies stay in memory and never survive a restart.
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

  /// Marks in-memory guest state immediately; storage cleanup failures surface
  /// as [SessionNotice.storageError] because the stale payload is unremovable.
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

/// Split so tests can reuse the payload codec without the plugin.
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
