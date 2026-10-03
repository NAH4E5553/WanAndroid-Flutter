/// 把已登录载荷串行写入加密存储并能读回。写入失败必须可观测,
/// 使会话切换能上报存储错误,
/// 而不是静默伪装成成功。
abstract interface class SessionStorage {
  Future<String?> read();

  Future<void> write(String? payload);
}
