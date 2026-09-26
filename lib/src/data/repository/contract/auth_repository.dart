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
  });

  final bool loading;
  final bool authenticated;
  final bool unverified;
  final bool expiredNotice;
  final bool storageNotice;
  final String? displayName;
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
