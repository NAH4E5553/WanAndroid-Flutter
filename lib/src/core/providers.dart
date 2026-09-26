import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_storage.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/collection_repository.dart';

/// Contract-level providers for the app layer and Feature ViewModels.
/// Feature Views must depend on their ViewModel providers instead. Defaults
/// throw; the production bootstrap overrides them.

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw StateError('Auth repository is not configured'),
);

final collectionRepositoryProvider = Provider<CollectionRepository>(
  (ref) => throw StateError('Collection repository is not configured'),
);

/// The theme controller only needs core-level storage, so a working in-memory
/// default keeps lightweight tests rendering without overrides.
final themeControllerProvider = Provider<ThemeController>(
  (ref) => ThemeController(preferences: MemoryThemePreferences()),
);

class MemoryThemePreferences implements ThemeStorage {
  ({WanPalette palette, ThemeMode mode})? _saved;

  @override
  Future<({WanPalette palette, ThemeMode mode})?> read() async => _saved;

  @override
  Future<void> write(WanPalette palette, ThemeMode mode) async {
    _saved = (palette: palette, mode: mode);
  }
}
