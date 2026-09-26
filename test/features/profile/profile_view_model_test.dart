import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_storage.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/features/profile/view_model/profile_view_model.dart';

void main() {
  test(
    'profile view model owns auth, theme and logout repository access',
    () async {
      final _AuthFixture auth = _AuthFixture();
      final ThemeController theme = ThemeController(
        preferences: _MemoryThemeStorage(),
      );
      await theme.load();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          themeControllerProvider.overrideWithValue(theme),
        ],
      );
      addTearDown(container.dispose);
      final ProviderSubscription<ProfileUiState> subscription = container
          .listen(profileViewModelProvider, (_, _) {}, fireImmediately: true);
      addTearDown(subscription.close);

      expect(subscription.read().auth.authenticated, isTrue);
      await theme.apply(WanPalette.warmAmber, ThemeMode.dark);
      expect(subscription.read().palette, WanPalette.warmAmber);
      expect(subscription.read().mode, ThemeMode.dark);

      await container.read(profileViewModelProvider.notifier).logout();
      expect(subscription.read().auth.authenticated, isFalse);
      expect(subscription.read().loggingOut, isFalse);
      expect(subscription.read().logoutNotice, '本机已退出，服务器退出未确认。');
    },
  );
}

final class _MemoryThemeStorage implements ThemeStorage {
  @override
  Future<ThemeSelection?> read() async => null;

  @override
  Future<void> write(WanPalette palette, ThemeMode mode) async {}
}

final class _AuthFixture extends ChangeNotifier implements AuthRepository {
  bool authenticated = true;

  @override
  AuthStateView view() => AuthStateView(
    loading: false,
    authenticated: authenticated,
    unverified: false,
    expiredNotice: false,
    storageNotice: false,
    displayName: authenticated ? '测试用户' : null,
  );

  @override
  Future<DataResult<void>> login(
    String username,
    String password, {
    RequestCancellation cancellation = const LiveRequestCancellation(),
  }) async => const DataSuccess<void>(null);

  @override
  Future<LogoutOutcome> logout() async {
    authenticated = false;
    notifyListeners();
    return const LogoutOutcome(
      generation: 1,
      remote: DataFailure<void>(DataError.network),
    );
  }

  @override
  Future<DataResult<void>> restore() async => const DataSuccess<void>(null);
}
