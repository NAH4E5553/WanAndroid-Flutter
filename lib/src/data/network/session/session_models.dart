import 'package:wanandroid_flutter/src/data/network/session/web_cookie.dart';
import 'package:wanandroid_flutter/src/model/user.dart';

enum SessionPhase { loading, guest, verifying, authenticated, unverified }

enum SessionNotice { none, expired, storageError }

/// 不可变的会话视图；`generation` 在每次账号状态切换时递增。
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

  /// 用于账号相关响应提示的非凭据身份；跨进程重启
  /// 绝不复用。
  String? authenticatedVersionKey(String instanceKey) =>
      authenticated ? '$instanceKey:$generation' : null;
}

/// 每个请求各自的身份，同时把登录与分离登出与共享会话隔离开，
/// 与已冻结的契约保持一致。
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
