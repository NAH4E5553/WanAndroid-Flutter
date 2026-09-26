import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_storage.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/features/auth/navigation/auth_navigation.dart';
import 'package:wanandroid_flutter/src/features/profile/view/theme_settings_screen.dart';

class _MemoryPrefs implements ThemeStorage {
  @override
  Future<({WanPalette palette, ThemeMode mode})?> read() async => null;

  @override
  Future<void> write(WanPalette palette, ThemeMode mode) async {}
}

class _FailingThemePreferences implements ThemeStorage {
  @override
  Future<({WanPalette palette, ThemeMode mode})?> read() async => null;

  @override
  Future<void> write(WanPalette palette, ThemeMode mode) async {
    throw StateError('disk full');
  }
}

class _ReadFailingThemePreferences implements ThemeStorage {
  @override
  Future<({WanPalette palette, ThemeMode mode})?> read() async {
    throw StateError('unreadable preferences');
  }

  @override
  Future<void> write(WanPalette palette, ThemeMode mode) async {}
}

class _SavedThemePreferences implements ThemeStorage {
  _SavedThemePreferences(this.selection);

  final ({WanPalette palette, ThemeMode mode}) selection;

  @override
  Future<({WanPalette palette, ThemeMode mode})?> read() async => selection;

  @override
  Future<void> write(WanPalette palette, ThemeMode mode) async {}
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

  testWidgets('every failed save reports feedback, including mode changes', (
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

    await tester.tap(find.text('莓果玫瑰'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('主题保存失败，已恢复原设置'), findsOneWidget);

    ScaffoldMessenger.of(tester.element(find.byType(ThemeSettingsScreen)))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('主题保存失败，已恢复原设置'), findsOneWidget);
    expect(controller.mode, ThemeMode.system);
  });

  testWidgets(
    'theme read failure uses defaults and shows the baseline warning',
    (WidgetTester tester) async {
      final ThemeController controller = ThemeController(
        preferences: _ReadFailingThemePreferences(),
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

      expect(controller.loadStatus, ThemeLoadStatus.readFailed);
      expect(find.text('无法读取已保存主题，当前使用默认设置'), findsOneWidget);
      expect(controller.palette, WanPalette.slateBlue);
      expect(controller.mode, ThemeMode.system);
    },
  );

  testWidgets(
    'dark selected mode uses the active container color and contrast',
    (WidgetTester tester) async {
      final ThemeController controller = ThemeController(
        preferences: _SavedThemePreferences((
          palette: WanPalette.slateBlue,
          mode: ThemeMode.dark,
        )),
      );
      await controller.load();
      final ThemeData darkTheme = wanTheme(
        palette: WanPalette.slateBlue,
        brightness: Brightness.dark,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [themeControllerProvider.overrideWithValue(controller)],
          child: MaterialApp(
            theme: darkTheme,
            home: ThemeSettingsScreen(onBack: () {}),
          ),
        ),
      );

      final Text selectedLabel = tester.widget<Text>(find.text('深色'));
      final AnimatedContainer selectedSegment = tester
          .widget<AnimatedContainer>(
            find
                .ancestor(
                  of: find.text('深色'),
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          );
      final BoxDecoration decoration =
          selectedSegment.decoration! as BoxDecoration;
      expect(decoration.color, darkTheme.colorScheme.primaryContainer);
      expect(
        selectedLabel.style?.color,
        darkTheme.colorScheme.onPrimaryContainer,
      );
      expect(decoration.color, isNot(selectedLabel.style?.color));
    },
  );

  testWidgets('theme page shows palette cards, swatches and mode segments', (
    WidgetTester tester,
  ) async {
    final ThemeController controller = ThemeController(
      preferences: _MemoryPrefs(),
    );
    await controller.load();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [themeControllerProvider.overrideWithValue(controller)],
        child: MaterialApp(home: ThemeSettingsScreen(onBack: () {})),
      ),
    );
    await tester.pumpAndSettle();
    // Four palette cards by name.
    for (final String name in <String>['墨青绿', '石板蓝', '暖琥珀', '莓果玫瑰']) {
      expect(find.text(name), findsOneWidget);
    }
    // Selected card carries exactly one check badge (default 石板蓝).
    expect(find.byIcon(Icons.check), findsOneWidget);
    // Mode segments exist.
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    // Selecting a card applies the palette.
    await tester.tap(find.text('暖琥珀'));
    await tester.pumpAndSettle();
    expect(controller.palette, WanPalette.warmAmber);
    expect(find.byIcon(Icons.check), findsOneWidget);
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
        child: MaterialApp(
          home: buildLoginScreen(onBack: () {}, onLoggedIn: () {}),
        ),
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, '请输入手机号'), '12345');
    await tester.tap(find.widgetWithText(TextField, '请输入密码'));
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
        child: MaterialApp(
          home: buildLoginScreen(onBack: () {}, onLoggedIn: () {}),
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextField, '请输入手机号'),
      '13800138000',
    );
    await tester.enterText(find.widgetWithText(TextField, '请输入密码'), 'secret');
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
  Future<DataResult<void>> login(
    String username,
    String password, {
    RequestCancellation cancellation = const LiveRequestCancellation(),
  }) async {
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
  Future<DataResult<void>> login(
    String username,
    String password, {
    RequestCancellation cancellation = const LiveRequestCancellation(),
  }) async => const DataFailure<void>(DataError.service);

  @override
  Future<DataResult<void>> restore() async => const DataSuccess<void>(null);

  @override
  Future<LogoutOutcome> logout() async =>
      LogoutOutcome(generation: 1, remote: const DataSuccess<void>(null));
}
