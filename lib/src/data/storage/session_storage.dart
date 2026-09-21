/// Serializes the signed-in payload to encrypted storage and back. A write
/// failure must be observable so session transitions can report storage
/// errors instead of silently pretending success.
abstract interface class SessionStorage {
  Future<String?> read();

  Future<void> write(String? payload);
}
