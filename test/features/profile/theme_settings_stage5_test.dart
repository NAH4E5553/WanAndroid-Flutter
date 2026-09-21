import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_storage.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/features/auth/view/login_screen.dart';
import 'package:wanandroid_flutter/src/features/profile/view/theme_settings_screen.dart';

class _FailingThemePreferences implements ThemeStorage {
  @override
  Future<({WanPalette palette, ThemeMode mode})?> read() async => null;

  @override
  Future<void> write(WanPalette palette, ThemeMode mode) async {
    throw StateError('disk full');
  }
}

void main() {
  testWidgets('theme save failure rolls the selection back', (
    WidgetTester tester,
  ) async {
    final ThemeController controller = ThemeController(
      preferences: _FailingThemePreferences(),
    );
    await controller.load();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [themeControllerProvider.overrideWithValue(controller)],
        child: MaterialApp(
          theme: wanTheme(brightness: Brightness.light),
          home: ThemeSettingsScreen(onBack: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('莓果玫瑰'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.saveFailed, isTrue);
    expect(controller.palette, WanPalette.slateBlue);
    expect(find.text('主题保存失败，已恢复原设置'), findsOneWidget);
  });

  testWidgets('login rejects a malformed phone number before submitting', (
    WidgetTester tester,
  ) async {
    bool submitted = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _RecordingAuthRepository(onSubmit: () => submitted = true),
          ),
        ],
        child: MaterialApp(home: LoginScreen(onBack: () {})),
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, '手机号'), '12345');
    await tester.tap(find.widgetWithText(TextField, '密码'));
    await tester.pump();
    expect(submitted, isFalse);
    expect(find.text('手机号输入有误，请重新输入'), findsOneWidget);
  });

  testWidgets('login rejects a service rejection with the baseline message', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FailingAuthRepository()),
        ],
        child: MaterialApp(home: LoginScreen(onBack: () {})),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextField, '手机号'),
      '13800138000',
    );
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'secret');
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, '登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '登录'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('登录未成功，请检查手机号和密码后重试'), findsOneWidget);
  });
}

class _RecordingAuthRepository implements AuthRepository {
  _RecordingAuthRepository({required this.onSubmit});

  final VoidCallback onSubmit;

  @override
  AuthStateView view() => AuthStateView(
    loading: false,
    authenticated: false,
    unverified: false,
    expiredNotice: false,
    storageNotice: false,
    displayName: null,
  );

  @override
  void addListener(void Function() listener) {}

  @override
  void removeListener(void Function() listener) {}

  @override
  Future<DataResult<void>> login(String username, String password) async {
    onSubmit();
    return const DataSuccess<void>(null);
  }

  @override
  Future<DataResult<void>> restore() async => const DataSuccess<void>(null);

  @override
  Future<LogoutOutcome> logout() async =>
      LogoutOutcome(generation: 1, remote: const DataSuccess<void>(null));
}

class _FailingAuthRepository implements AuthRepository {
  @override
  AuthStateView view() => AuthStateView(
    loading: false,
    authenticated: false,
    unverified: false,
    expiredNotice: false,
    storageNotice: false,
    displayName: null,
  );

  @override
  void addListener(void Function() listener) {}

  @override
  void removeListener(void Function() listener) {}

  @override
  Future<DataResult<void>> login(String username, String password) async =>
      const DataFailure<void>(DataError.service);

  @override
  Future<DataResult<void>> restore() async => const DataSuccess<void>(null);

  @override
  Future<LogoutOutcome> logout() async =>
      LogoutOutcome(generation: 1, remote: const DataSuccess<void>(null));
}
