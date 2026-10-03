import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wanandroid_flutter/src/data/storage/session_storage.dart';

/// 设备上加密存储的会话载荷。Android 将其排除在备份之外,
/// iOS 通过下方平台选项使其不进入云端。
final class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(synchronizable: false),
          );

  static const String _key = 'wan.session.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String? payload) async {
    if (payload == null) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(key: _key, value: payload);
    }
  }
}
