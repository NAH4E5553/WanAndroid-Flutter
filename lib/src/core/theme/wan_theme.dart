import 'package:flutter/material.dart';

enum WanPalette { inkTeal, slateBlue, warmAmber, berryRose }

@immutable
class WanSpacing extends ThemeExtension<WanSpacing> {
  const WanSpacing({
    this.small = 8,
    this.medium = 12,
    this.page = 16,
    this.section = 24,
  });

  final double small;
  final double medium;
  final double page;
  final double section;

  @override
  WanSpacing copyWith({
    double? small,
    double? medium,
    double? page,
    double? section,
  }) => WanSpacing(
    small: small ?? this.small,
    medium: medium ?? this.medium,
    page: page ?? this.page,
    section: section ?? this.section,
  );

  @override
  WanSpacing lerp(covariant WanSpacing? other, double t) {
    if (other == null) {
      return this;
    }
    return WanSpacing(
      small: lerpDouble(small, other.small, t),
      medium: lerpDouble(medium, other.medium, t),
      page: lerpDouble(page, other.page, t),
      section: lerpDouble(section, other.section, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

@immutable
class WanShapes extends ThemeExtension<WanShapes> {
  const WanShapes({this.small = 8, this.medium = 12, this.large = 24});

  final double small;
  final double medium;
  final double large;

  @override
  WanShapes copyWith({double? small, double? medium, double? large}) =>
      WanShapes(
        small: small ?? this.small,
        medium: medium ?? this.medium,
        large: large ?? this.large,
      );

  @override
  WanShapes lerp(covariant WanShapes? other, double t) {
    if (other == null) {
      return this;
    }
    return WanShapes(
      small: WanSpacing.lerpDouble(small, other.small, t),
      medium: WanSpacing.lerpDouble(medium, other.medium, t),
      large: WanSpacing.lerpDouble(large, other.large, t),
    );
  }
}

extension WanThemeContext on BuildContext {
  WanSpacing get spacing => Theme.of(this).extension<WanSpacing>()!;
  WanShapes get wanShapes => Theme.of(this).extension<WanShapes>()!;
}

ThemeData wanTheme({
  WanPalette palette = WanPalette.slateBlue,
  required Brightness brightness,
}) {
  final bool dark = brightness == Brightness.dark;
  final ColorScheme colors = _colorScheme(palette, dark: dark);
  const WanShapes shapeTokens = WanShapes();
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    textTheme: _typography(colors),
    extensions: const <ThemeExtension<dynamic>>[WanSpacing(), shapeTokens],
    cardTheme: CardThemeData(
      color: colors.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(shapeTokens.medium),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surfaceContainerLowest,
      elevation: 0,
      indicatorColor: colors.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll<TextStyle>(
        _typography(colors).labelMedium!,
      ),
    ),
  );
}

TextTheme _typography(ColorScheme colors) => TextTheme(
  headlineLarge: TextStyle(
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w600,
    color: colors.onSurface,
  ),
  headlineMedium: TextStyle(
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w600,
    color: colors.onSurface,
  ),
  headlineSmall: TextStyle(
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
    color: colors.onSurface,
  ),
  titleLarge: TextStyle(
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w500,
    color: colors.onSurface,
  ),
  titleMedium: TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w500,
    color: colors.onSurface,
  ),
  bodyLarge: TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    color: colors.onSurface,
  ),
  bodyMedium: TextStyle(
    fontSize: 14,
    height: 22 / 14,
    fontWeight: FontWeight.w400,
    color: colors.onSurface,
  ),
  bodySmall: TextStyle(
    fontSize: 12,
    height: 18 / 12,
    fontWeight: FontWeight.w400,
    color: colors.onSurface,
  ),
  labelLarge: TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    color: colors.onSurface,
  ),
  labelMedium: TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    color: colors.onSurface,
  ),
);

class _Accent {
  const _Accent({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
  });

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
}

class _PalettePair {
  const _PalettePair(this.light, this.dark);

  final _Accent light;
  final _Accent dark;
}

const Map<WanPalette, _PalettePair> _palettes = <WanPalette, _PalettePair>{
  WanPalette.inkTeal: _PalettePair(
    _Accent(
      primary: Color(0xFF006B5B),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF8EF7DC),
      onPrimaryContainer: Color(0xFF00201A),
      secondary: Color(0xFF4A635C),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFCCE8DF),
      onSecondaryContainer: Color(0xFF06201A),
      tertiary: Color(0xFF456179),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFCCE5FF),
      onTertiaryContainer: Color(0xFF001E30),
    ),
    _Accent(
      primary: Color(0xFF82D5C2),
      onPrimary: Color(0xFF00382F),
      primaryContainer: Color(0xFF005045),
      onPrimaryContainer: Color(0xFFA3F2DD),
      secondary: Color(0xFFB0CCC3),
      onSecondary: Color(0xFF1C352F),
      secondaryContainer: Color(0xFF334C46),
      onSecondaryContainer: Color(0xFFCCE8DF),
      tertiary: Color(0xFFACCAE5),
      onTertiary: Color(0xFF143348),
      tertiaryContainer: Color(0xFF2C4960),
      onTertiaryContainer: Color(0xFFCCE5FF),
    ),
  ),
  WanPalette.slateBlue: _PalettePair(
    _Accent(
      primary: Color(0xFF315F84),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFCEE5FF),
      onPrimaryContainer: Color(0xFF0B1D2A),
      secondary: Color(0xFF50606F),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFD3E5F6),
      onSecondaryContainer: Color(0xFF0D1D29),
      tertiary: Color(0xFF65587A),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFEBDCFF),
      onTertiaryContainer: Color(0xFF201A2D),
    ),
    _Accent(
      primary: Color(0xFF9CCAFA),
      onPrimary: Color(0xFF003353),
      primaryContainer: Color(0xFF164766),
      onPrimaryContainer: Color(0xFFCEE5FF),
      secondary: Color(0xFFB7C9D9),
      onSecondary: Color(0xFF22323F),
      secondaryContainer: Color(0xFF394956),
      onSecondaryContainer: Color(0xFFD3E5F6),
      tertiary: Color(0xFFCEC0E8),
      onTertiary: Color(0xFF362B49),
      tertiaryContainer: Color(0xFF4D4261),
      onTertiaryContainer: Color(0xFFEBDCFF),
    ),
  ),
  WanPalette.warmAmber: _PalettePair(
    _Accent(
      primary: Color(0xFF795900),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFFFDF90),
      onPrimaryContainer: Color(0xFF261A00),
      secondary: Color(0xFF6B5D3F),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFF4E0BB),
      onSecondaryContainer: Color(0xFF241A04),
      tertiary: Color(0xFF4B6548),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFCDEBC5),
      onTertiaryContainer: Color(0xFF09210A),
    ),
    _Accent(
      primary: Color(0xFFEFC15C),
      onPrimary: Color(0xFF402D00),
      primaryContainer: Color(0xFF5C4300),
      onPrimaryContainer: Color(0xFFFFDF90),
      secondary: Color(0xFFD7C4A0),
      onSecondary: Color(0xFF3B2F15),
      secondaryContainer: Color(0xFF52462A),
      onSecondaryContainer: Color(0xFFF4E0BB),
      tertiary: Color(0xFFB1CFA9),
      onTertiary: Color(0xFF1E371E),
      tertiaryContainer: Color(0xFF344D33),
      onTertiaryContainer: Color(0xFFCDEBC5),
    ),
  ),
  WanPalette.berryRose: _PalettePair(
    _Accent(
      primary: Color(0xFF8A3F62),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFFFD9E5),
      onPrimaryContainer: Color(0xFF3A071F),
      secondary: Color(0xFF74565F),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFFFD9E1),
      onSecondaryContainer: Color(0xFF2B151C),
      tertiary: Color(0xFF7C5635),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFFFDCC0),
      onTertiaryContainer: Color(0xFF2E1500),
    ),
    _Accent(
      primary: Color(0xFFFFAFCE),
      onPrimary: Color(0xFF53112F),
      primaryContainer: Color(0xFF6D2949),
      onPrimaryContainer: Color(0xFFFFD9E5),
      secondary: Color(0xFFE3BDC7),
      onSecondary: Color(0xFF422931),
      secondaryContainer: Color(0xFF5A3F47),
      onSecondaryContainer: Color(0xFFFFD9E1),
      tertiary: Color(0xFFEFBF94),
      onTertiary: Color(0xFF48290C),
      tertiaryContainer: Color(0xFF623F20),
      onTertiaryContainer: Color(0xFFFFDCC0),
    ),
  ),
};

/// Three representative swatches for the active brightness of a palette.
class PaletteSwatchColors {
  const PaletteSwatchColors({
    required this.primary,
    required this.secondary,
    required this.container,
  });

  final Color primary;
  final Color secondary;
  final Color container;
}

PaletteSwatchColors paletteSwatchColors(
  WanPalette palette, {
  required Brightness brightness,
}) {
  final _PalettePair pair = _palettes[palette]!;
  final _Accent accent = brightness == Brightness.dark ? pair.dark : pair.light;
  return PaletteSwatchColors(
    primary: accent.primary,
    secondary: accent.secondary,
    container: accent.primaryContainer,
  );
}

ColorScheme _colorScheme(WanPalette palette, {required bool dark}) {
  final _PalettePair pair = _palettes[palette]!;
  final _Accent accent = dark ? pair.dark : pair.light;
  final _Accent lightAccent = pair.light;
  final _Accent darkAccent = pair.dark;
  return ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: accent.primary,
    onPrimary: accent.onPrimary,
    primaryContainer: accent.primaryContainer,
    onPrimaryContainer: accent.onPrimaryContainer,
    primaryFixed: lightAccent.primaryContainer,
    primaryFixedDim: darkAccent.primary,
    onPrimaryFixed: lightAccent.onPrimaryContainer,
    onPrimaryFixedVariant: darkAccent.primaryContainer,
    secondary: accent.secondary,
    onSecondary: accent.onSecondary,
    secondaryContainer: accent.secondaryContainer,
    onSecondaryContainer: accent.onSecondaryContainer,
    secondaryFixed: lightAccent.secondaryContainer,
    secondaryFixedDim: darkAccent.secondary,
    onSecondaryFixed: lightAccent.onSecondaryContainer,
    onSecondaryFixedVariant: darkAccent.secondaryContainer,
    tertiary: accent.tertiary,
    onTertiary: accent.onTertiary,
    tertiaryContainer: accent.tertiaryContainer,
    onTertiaryContainer: accent.onTertiaryContainer,
    tertiaryFixed: lightAccent.tertiaryContainer,
    tertiaryFixedDim: darkAccent.tertiary,
    onTertiaryFixed: lightAccent.onTertiaryContainer,
    onTertiaryFixedVariant: darkAccent.tertiaryContainer,
    error: dark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
    onError: dark ? const Color(0xFF690005) : Colors.white,
    errorContainer: dark ? const Color(0xFF93000A) : const Color(0xFFFFDAD6),
    onErrorContainer: dark ? const Color(0xFFFFDAD6) : const Color(0xFF410002),
    surface: dark ? const Color(0xFF111417) : const Color(0xFFF7F9FC),
    onSurface: dark ? const Color(0xFFE1E2E6) : const Color(0xFF191C1F),
    surfaceDim: dark ? const Color(0xFF111417) : const Color(0xFFD8DADF),
    surfaceBright: dark ? const Color(0xFF37393D) : const Color(0xFFF7F9FC),
    surfaceContainerLowest: dark ? const Color(0xFF0C0F12) : Colors.white,
    surfaceContainerLow: dark
        ? const Color(0xFF191C20)
        : const Color(0xFFF1F4F7),
    surfaceContainer: dark ? const Color(0xFF1D2024) : const Color(0xFFEBEEF2),
    surfaceContainerHigh: dark
        ? const Color(0xFF282A2E)
        : const Color(0xFFE5E9EC),
    surfaceContainerHighest: dark
        ? const Color(0xFF333539)
        : const Color(0xFFDFE3E7),
    onSurfaceVariant: dark ? const Color(0xFFC2C7CD) : const Color(0xFF42474D),
    outline: dark ? const Color(0xFF8C9197) : const Color(0xFF72777D),
    outlineVariant: dark ? const Color(0xFF42474D) : const Color(0xFFC2C7CD),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: dark ? const Color(0xFFE1E2E6) : const Color(0xFF2E3135),
    onInverseSurface: dark ? const Color(0xFF2E3135) : const Color(0xFFEFF1F5),
    inversePrimary: dark ? lightAccent.primary : darkAccent.primary,
    surfaceTint: accent.primary,
    // Compose still exposes surfaceVariant. Flutter maps new components to
    // container roles, but keeping this exact value preserves legacy defaults.
    // ignore: deprecated_member_use
    surfaceVariant: dark ? const Color(0xFF42474D) : const Color(0xFFDEE3E8),
  );
}
