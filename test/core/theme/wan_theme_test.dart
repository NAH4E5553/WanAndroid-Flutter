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
    expect(light.colorScheme.inversePrimary, const Color(0xFF9CCAFA));
    expect(light.colorScheme.inverseSurface, const Color(0xFF2E3135));
    expect(light.colorScheme.onInverseSurface, const Color(0xFFEFF1F5));
    expect(light.colorScheme.surfaceDim, const Color(0xFFD8DADF));
    expect(dark.colorScheme.inversePrimary, const Color(0xFF315F84));
    expect(dark.colorScheme.surfaceBright, const Color(0xFF37393D));
    expect(dark.colorScheme.onInverseSurface, const Color(0xFF2E3135));
    expect(light.colorScheme.primaryFixed, const Color(0xFFCEE5FF));
    expect(light.colorScheme.primaryFixedDim, const Color(0xFF9CCAFA));
    expect(dark.colorScheme.primaryFixed, const Color(0xFFCEE5FF));
    expect(dark.colorScheme.primaryFixedDim, const Color(0xFF9CCAFA));
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

  test('palette swatches follow the active brightness', () {
    final PaletteSwatchColors light = paletteSwatchColors(
      WanPalette.slateBlue,
      brightness: Brightness.light,
    );
    final PaletteSwatchColors dark = paletteSwatchColors(
      WanPalette.slateBlue,
      brightness: Brightness.dark,
    );

    expect(light.primary, const Color(0xFF315F84));
    expect(light.secondary, const Color(0xFF50606F));
    expect(light.container, const Color(0xFFCEE5FF));
    expect(dark.primary, const Color(0xFF9CCAFA));
    expect(dark.secondary, const Color(0xFFB7C9D9));
    expect(dark.container, const Color(0xFF164766));
  });
}
