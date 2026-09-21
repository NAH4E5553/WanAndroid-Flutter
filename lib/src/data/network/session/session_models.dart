import 'package:wanandroid_flutter/src/data/network/session/web_cookie.dart';
import 'package:wanandroid_flutter/src/model/user.dart';

enum SessionPhase { loading, guest, verifying, authenticated, unverified }

enum SessionNotice { none, expired, storageError }

/// Immutable session view; `generation` advances on every account transition.
class SessionSnapshot {
  const SessionSnapshot({
    this.phase = SessionPhase.loading,
    this.user,
    this.generation = 0,
    this.notice = SessionNotice.none,
  });

  final SessionPhase phase;
  final User? user;
  final int generation;
  final SessionNotice notice;

  SessionSnapshot copyWith({
    SessionPhase? phase,
    User? user,
    int? generation,
    SessionNotice? notice,
  }) => SessionSnapshot(
    phase: phase ?? this.phase,
    user: user ?? this.user,
    generation: generation ?? this.generation,
    notice: notice ?? this.notice,
  );

  bool get authenticated => phase == SessionPhase.authenticated;

  /// Non-credential identity for account-bound response hints; never reused
  /// across process restarts.
  String? authenticatedVersionKey(String instanceKey) =>
      authenticated ? '$instanceKey:$generation' : null;
}

/// Per-request identity also isolating login and detached logout from the
/// shared session, mirroring the frozen contract.
class SessionRequest {
  SessionRequest.normal(int generation)
    : this._internal(generation, mode: SessionRequestMode.normal);

  const SessionRequest._internal(
    this.generation, {
    required this.mode,
    this.logoutCookies = const <WebCookie>[],
  });

  factory SessionRequest.login(int generation) =>
      SessionRequest._internal(generation, mode: SessionRequestMode.login);

  factory SessionRequest.detachedLogout(
    int generation,
    List<WebCookie> cookies,
  ) => SessionRequest._internal(
    generation,
    mode: SessionRequestMode.logout,
    logoutCookies: cookies,
  );

  final int generation;
  final SessionRequestMode mode;
  final List<WebCookie> logoutCookies;
}

enum SessionRequestMode { normal, login, logout }
