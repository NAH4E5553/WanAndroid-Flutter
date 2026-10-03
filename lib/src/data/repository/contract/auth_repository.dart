import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';

enum LogoutRemoteResult { confirmed, unconfirmed }

class LogoutOutcome {
  const LogoutOutcome({required this.generation, required this.remote});

  /// 当本地分离在存储环节失败时为 null;账号仍保持挂载。
  final int? generation;
  final DataResult<void> remote;

  bool get localDetached => generation != null;
}

/// 由权威存储派生的、面向 UI 的会话状态,从而 View 永远不必直接接触
/// 会话存储或 Cookie 类型。
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

  /// 服务端稳定的账号 id,用于本地按账号区分的事实(如本地头像)。
  /// 未挂载账号时为 null。
  final int? userId;

  /// 用于已验证登录的操作身份:不透明且非凭据。它在每次 login/detach
  /// 时都会变化,且跨进程重启绝不复用,
  /// 因此调用方必须将其视为“当前操作身份”,而不是持久不变的账号键。
  /// 未验证期间为 null。
  final String? accountVersionKey;
}

abstract interface class AuthRepository {
  void addListener(void Function() listener);

  void removeListener(void Function() listener);

  /// 当前面向 UI 的会话视图。
  AuthStateView view();

  /// 恢复已持久化的会话:可验证的转为已认证,
  /// 已过期的被清除,
  /// 网络失败则保留未验证会话,让公开浏览继续可用。
  Future<DataResult<void>> restore();

  Future<DataResult<void>> login(
    String username,
    String password, {
    RequestCancellation cancellation = const LiveRequestCancellation(),
  });

  Future<LogoutOutcome> logout();
}
