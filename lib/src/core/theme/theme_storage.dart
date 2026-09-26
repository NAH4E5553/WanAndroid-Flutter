import 'package:flutter/material.dart' show ThemeMode;
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';

typedef ThemeSelection = ({WanPalette palette, ThemeMode mode});

/// Persisted appearance selection. Throws on storage failure so callers can
/// roll the visible state back instead of reporting false success.
abstract interface class ThemeStorage {
  Future<ThemeSelection?> read();

  /// Persists [palette] and [mode] as one logical value.
  Future<void> write(WanPalette palette, ThemeMode mode);
}
