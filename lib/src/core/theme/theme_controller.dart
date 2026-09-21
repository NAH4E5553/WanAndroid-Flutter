import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:wanandroid_flutter/src/core/theme/theme_storage.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';

enum ThemeLoadStatus { loading, ready, readFailed }

/// Applies theme selections immediately, persists them, and rolls the visible
/// state back when persistence fails. Read failures keep defaults but surface
/// [ThemeLoadStatus.readFailed] so the UI can say defaults are in use.
class ThemeController extends ChangeNotifier {
  ThemeController({required this._preferences});

  final ThemeStorage _preferences;

  ThemeLoadStatus loadStatus = ThemeLoadStatus.loading;
  WanPalette palette = WanPalette.slateBlue;
  ThemeMode mode = ThemeMode.system;
  bool saving = false;
  bool saveFailed = false;

  bool get ready => loadStatus != ThemeLoadStatus.loading;

  Future<void> load() async {
    try {
      final ({WanPalette palette, ThemeMode mode})? saved = await _preferences
          .read();
      if (saved != null) {
        palette = saved.palette;
        mode = saved.mode;
      }
      loadStatus = ThemeLoadStatus.ready;
    } on Object {
      loadStatus = ThemeLoadStatus.readFailed;
    }
    notifyListeners();
  }

  /// Applies first, then persists; a persistence failure restores the previous
  /// selection and reports [saveFailed] instead of pretending success.
  Future<void> apply(WanPalette newPalette, ThemeMode newMode) async {
    if (!ready || saving) {
      return;
    }
    final WanPalette previousPalette = palette;
    final ThemeMode previousMode = mode;
    saveFailed = false;
    saving = true;
    palette = newPalette;
    mode = newMode;
    notifyListeners();
    try {
      await _preferences.write(newPalette, newMode);
    } on Object {
      palette = previousPalette;
      mode = previousMode;
      saveFailed = true;
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
