import 'dart:async';

/// 登录、登出与恢复共用的唯一异步闸门。每次会话状态切换都在此排队，
/// 因此旧的延迟写入绝不会与更新的账号意图交错，
/// 遵循已冻结的会话契约。
class SessionCommitCoordinator {
  Future<Object?> _tail = Future<Object?>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final Future<Object?> current = _tail;
    final Completer<Object?> gate = Completer<Object?>();
    _tail = gate.future;
    return current.then((_) => operation()).whenComplete(() {
      gate.complete();
    });
  }
}
