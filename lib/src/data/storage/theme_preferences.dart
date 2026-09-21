import 'package:flutter/material.dart' show ThemeMode;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_storage.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';

final class SharedPreferencesThemePreferences implements ThemeStorage {
  SharedPreferencesThemePreferences({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _paletteKey = 'theme.palette';
  static const String _modeKey = 'theme.mode';

  final SharedPreferencesAsync _preferences;

  @override
  Future<({WanPalette palette, ThemeMode mode})?> read() async {
    final String? paletteName = await _preferences.getString(_paletteKey);
    final String? modeName = await _preferences.getString(_modeKey);
    if (paletteName == null || modeName == null) {
      return null;
    }
    final WanPalette? palette = WanPalette.values.asNameMap()[paletteName];
    final ThemeMode? mode = ThemeMode.values.asNameMap()[modeName];
    if (palette == null || mode == null) {
      return null;
    }
    return (palette: palette, mode: mode);
  }

  @override
  Future<void> write(WanPalette palette, ThemeMode mode) async {
    await _preferences.setString(_paletteKey, palette.name);
    await _preferences.setString(_modeKey, mode.name);
  }
}
