import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';

void main() {
  test('slate blue maps exact frozen light and dark roles', () {
    final ThemeData light = wanTheme(brightness: Brightness.light);
    final ThemeData dark = wanTheme(brightness: Brightness.dark);

    expect(light.colorScheme.primary, const Color(0xFF315F84));
    expect(light.colorScheme.surface, const Color(0xFFF7F9FC));
    expect(light.colorScheme.surfaceContainerLow, const Color(0xFFF1F4F7));
    expect(dark.colorScheme.primary, const Color(0xFF9CCAFA));
    expect(dark.colorScheme.surface, const Color(0xFF111417));
    expect(dark.colorScheme.surfaceContainerLow, const Color(0xFF191C20));
  });

  test('all four palettes expose distinct exact primary roles', () {
    final Set<Color> primaries = WanPalette.values
        .map(
          (WanPalette palette) => wanTheme(
            palette: palette,
            brightness: Brightness.light,
          ).colorScheme.primary,
        )
        .toSet();

    expect(primaries, hasLength(4));
    expect(primaries, contains(const Color(0xFF006B5B)));
    expect(primaries, contains(const Color(0xFF795900)));
    expect(primaries, contains(const Color(0xFF8A3F62)));
  });

  test('typography and token extensions match the Android baseline', () {
    final ThemeData theme = wanTheme(brightness: Brightness.light);

    expect(theme.textTheme.headlineLarge?.fontSize, 32);
    expect(theme.textTheme.headlineLarge?.height, 40 / 32);
    expect(theme.textTheme.titleMedium?.fontSize, 16);
    expect(theme.extension<WanSpacing>()?.page, 16);
    expect(theme.extension<WanShapes>()?.medium, 12);
  });
}
