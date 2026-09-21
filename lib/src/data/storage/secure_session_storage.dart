import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wanandroid_flutter/src/data/storage/session_storage.dart';

/// Encrypted on-device session payload. Android excludes it from backups and
/// iOS keeps it off-cloud via the platform options below.
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
