import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';

enum LogoutRemoteResult { confirmed, unconfirmed }

class LogoutOutcome {
  const LogoutOutcome({required this.generation, required this.remote});

  /// Null when local detach failed on storage; the account is still attached.
  final int? generation;
  final DataResult<void> remote;

  bool get localDetached => generation != null;
}

/// UI-facing session state derived from the authoritative store, so views
/// never touch session storage or cookie types directly.
class AuthStateView {
  const AuthStateView({
    required this.loading,
    required this.authenticated,
    required this.unverified,
    required this.expiredNotice,
    required this.storageNotice,
    required this.displayName,
    this.userId,
    this.accountVersionKey,
  });

  final bool loading;
  final bool authenticated;
  final bool unverified;
  final bool expiredNotice;
  final bool storageNotice;
  final String? displayName;

  /// Server-stable account id for local per-account facts (e.g. the local
  /// avatar). Null when no account is attached.
  final int? userId;

  /// Opaque non-credential operation identity for the verified login. Changes
  /// on every login/detach and is never reused across process restarts, so
  /// callers must treat it as "current operation identity", not a durable
  /// account key. Null while unverified.
  final String? accountVersionKey;
}

abstract interface class AuthRepository {
  void addListener(void Function() listener);

  void removeListener(void Function() listener);

  /// Current UI-facing session view.
  AuthStateView view();

  /// Resumes a persisted session: verifiable ones become authenticated,
  /// expired ones clear, network failures leave an unverified session that
  /// keeps public browsing alive.
  Future<DataResult<void>> restore();

  Future<DataResult<void>> login(
    String username,
    String password, {
    RequestCancellation cancellation = const LiveRequestCancellation(),
  });

  Future<LogoutOutcome> logout();
}
