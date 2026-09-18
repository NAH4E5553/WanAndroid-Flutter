import 'package:shared_preferences/shared_preferences.dart';

abstract interface class SearchHistoryStorage {
  Future<List<String>> read();

  Future<void> write(List<String> values);
}

final class SharedPreferencesSearchHistoryStorage
    implements SearchHistoryStorage {
  SharedPreferencesSearchHistoryStorage({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _key = 'search_history.recent';
  final SharedPreferencesAsync _preferences;

  @override
  Future<List<String>> read() async =>
      await _preferences.getStringList(_key) ?? const <String>[];

  @override
  Future<void> write(List<String> values) =>
      _preferences.setStringList(_key, values);
}
