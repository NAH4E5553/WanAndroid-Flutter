import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/features/auth/navigation/auth_navigation.dart';
import 'package:wanandroid_flutter/src/features/auth/state/login_ui_state.dart';
import 'package:wanandroid_flutter/src/features/auth/view/login_screen.dart';

void main() {
  testWidgets('UI-07 password done action submits and eye stays in the field', (
    WidgetTester tester,
  ) async {
    int submissions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          state: const LoginUiState(
            username: '13800138000',
            password: 'secret',
          ),
          onUsernameChanged: (_) {},
          onPasswordChanged: (_) {},
          onPasswordFocused: () {},
          onSubmit: () async {
            submissions++;
          },
          onBack: () {},
        ),
      ),
    );

    final TextField password = tester.widget<TextField>(
      find.widgetWithText(TextField, '请输入密码'),
    );
    expect(password.textInputAction, TextInputAction.done);
    expect(password.decoration?.suffixIcon, isA<IconButton>());
    expect(find.text('密码'), findsNothing);

    await tester.tap(find.widgetWithText(TextField, '请输入密码'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submissions, 1);
  });

  testWidgets(
    'UI-07 consent text does not overflow at 200 percent text scale',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: LoginScreen(
              state: const LoginUiState(),
              onUsernameChanged: (_) {},
              onPasswordChanged: (_) {},
              onPasswordFocused: () {},
              onSubmit: () async {},
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('《用户协议》'), findsOneWidget);
      expect(find.text('《隐私政策》'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('UI-07 system back cancels an in-flight login', (
    WidgetTester tester,
  ) async {
    final _PendingAuthRepository repository = _PendingAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: _LoginNavigationHarness()),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('open-login')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '请输入手机号'),
      '13800138000',
    );
    await tester.enterText(find.widgetWithText(TextField, '请输入密码'), 'secret');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, '登录'));
    await tester.tap(find.widgetWithText(ElevatedButton, '登录'));
    await tester.pump();
    expect(repository.started.isCompleted, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(repository.cancellation?.isCancelled, isTrue);
  });
}

class _PendingAuthRepository extends ChangeNotifier implements AuthRepository {
  final Completer<void> started = Completer<void>();
  RequestCancellation? cancellation;

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
  Future<DataResult<void>> login(
    String username,
    String password, {
    RequestCancellation cancellation = const LiveRequestCancellation(),
  }) async {
    this.cancellation = cancellation;
    started.complete();
    await cancellation.whenCancelled;
    throw const RequestCancelledException();
  }

  @override
  Future<DataResult<void>> restore() async => const DataSuccess<void>(null);

  @override
  Future<LogoutOutcome> logout() async =>
      LogoutOutcome(generation: 1, remote: const DataSuccess<void>(null));
}

class _LoginNavigationHarness extends StatelessWidget {
  const _LoginNavigationHarness();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ElevatedButton(
      key: const ValueKey<String>('open-login'),
      onPressed: () {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext routeContext) => buildLoginScreen(
              onBack: () => Navigator.of(routeContext).pop(),
              onLoggedIn: () => Navigator.of(routeContext).pop(),
            ),
          ),
        );
      },
      child: const Text('打开登录'),
    ),
  );
}
