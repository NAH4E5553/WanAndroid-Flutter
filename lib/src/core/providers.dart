import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_storage.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/avatar_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/collection_repository.dart';

/// 面向 app 层与 Feature ViewModel 的契约级 provider。
/// Feature View 必须改为依赖各自 ViewModel 的 provider。默认实现
/// 直接抛出异常;生产 bootstrap 会覆盖它们。

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw StateError('Auth repository is not configured'),
);

final collectionRepositoryProvider = Provider<CollectionRepository>(
  (ref) => throw StateError('Collection repository is not configured'),
);

final avatarRepositoryProvider = Provider<AvatarRepository>(
  (ref) => throw StateError('Avatar repository is not configured'),
);

/// 主题控制器只需要 core 层级的存储,因此一个可用的内存默认实现
/// 让轻量测试无需覆盖即可渲染。
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
