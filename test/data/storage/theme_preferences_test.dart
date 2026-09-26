import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/data/storage/theme_preferences.dart';

void main() {
  test('all theme selections round-trip through stable storage values', () {
    for (final WanPalette palette in WanPalette.values) {
      for (final ThemeMode mode in ThemeMode.values) {
        final decoded = decodeThemeSelection(
          encodeThemeSelection(palette, mode),
        );
        expect(decoded?.palette, palette);
        expect(decoded?.mode, mode);
      }
    }
  });

  test('storage values remain independent of Dart enum names', () {
    expect(encodeThemeSelection(WanPalette.inkTeal, ThemeMode.system), <String>[
      'ink_teal',
      'follow_system',
    ]);
    expect(encodeThemeSelection(WanPalette.berryRose, ThemeMode.dark), <String>[
      'berry_rose',
      'dark',
    ]);
  });

  test('malformed and future values fall back safely', () {
    expect(decodeThemeSelection(const <String>[]), isNull);
    expect(decodeThemeSelection(const <String>['slate_blue']), isNull);
    expect(
      decodeThemeSelection(const <String>['future_palette', 'dark']),
      isNull,
    );
    expect(
      decodeThemeSelection(const <String>['slate_blue', 'future_mode']),
      isNull,
    );
  });
}
