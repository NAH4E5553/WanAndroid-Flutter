import 'package:flutter/material.dart' show ThemeMode;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_storage.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';

final class SharedPreferencesThemePreferences implements ThemeStorage {
  SharedPreferencesThemePreferences({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _selectionKey = 'theme.selection.v1';
  static const String _legacyPaletteKey = 'theme.palette';
  static const String _legacyModeKey = 'theme.mode';

  final SharedPreferencesAsync _preferences;

  @override
  Future<ThemeSelection?> read() async {
    final List<String>? encoded = await _preferences.getStringList(
      _selectionKey,
    );
    if (encoded != null) {
      return decodeThemeSelection(encoded);
    }

    // Compatibility with the initial stage-5 implementation. New writes use
    // one value so palette and mode can no longer be partially committed.
    final String? paletteName = await _preferences.getString(_legacyPaletteKey);
    final String? modeName = await _preferences.getString(_legacyModeKey);
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
    await _preferences.setStringList(
      _selectionKey,
      encodeThemeSelection(palette, mode),
    );
  }
}

List<String> encodeThemeSelection(WanPalette palette, ThemeMode mode) =>
    <String>[_paletteStorageValues[palette]!, _modeStorageValues[mode]!];

ThemeSelection? decodeThemeSelection(List<String> encoded) {
  if (encoded.length != 2) {
    return null;
  }
  final WanPalette? palette = _palettesByStorageValue[encoded[0]];
  final ThemeMode? mode = _modesByStorageValue[encoded[1]];
  if (palette == null || mode == null) {
    return null;
  }
  return (palette: palette, mode: mode);
}

const Map<WanPalette, String> _paletteStorageValues = <WanPalette, String>{
  WanPalette.inkTeal: 'ink_teal',
  WanPalette.slateBlue: 'slate_blue',
  WanPalette.warmAmber: 'warm_amber',
  WanPalette.berryRose: 'berry_rose',
};

const Map<ThemeMode, String> _modeStorageValues = <ThemeMode, String>{
  ThemeMode.system: 'follow_system',
  ThemeMode.light: 'light',
  ThemeMode.dark: 'dark',
};

final Map<String, WanPalette> _palettesByStorageValue = _paletteStorageValues
    .map(
      (WanPalette key, String value) =>
          MapEntry<String, WanPalette>(value, key),
    );

final Map<String, ThemeMode> _modesByStorageValue = _modeStorageValues.map(
  (ThemeMode key, String value) => MapEntry<String, ThemeMode>(value, key),
);
