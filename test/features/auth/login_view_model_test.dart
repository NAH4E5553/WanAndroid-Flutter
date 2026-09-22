import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/features/auth/state/login_ui_state.dart';
import 'package:wanandroid_flutter/src/features/auth/view_model/login_view_model.dart';

void main() {
  test(
    'UI-07 malformed phone is rejected before repository submission',
    () async {
      final _ControllableAuthRepository repository =
          _ControllableAuthRepository();
      final _LoginHarness harness = _LoginHarness(repository);
      addTearDown(harness.dispose);

      harness.notifier
        ..usernameChanged('12345')
        ..passwordChanged('secret');
      await harness.notifier.submit();

      expect(repository.loginCalls, 0);
      expect(harness.state.phoneError, isTrue);
    },
  );

  test('UI-07 editing clears phone and server errors', () async {
    final _ControllableAuthRepository repository = _ControllableAuthRepository(
      loginResult: const DataFailure<void>(DataError.service),
    );
    final _LoginHarness harness = _LoginHarness(repository);
    addTearDown(harness.dispose);

    harness.notifier
      ..usernameChanged('13800138000')
      ..passwordChanged('secret');
    await harness.notifier.submit();
    expect(harness.state.error, DataError.service);

    harness.notifier.usernameChanged('13900139000');
    expect(harness.state.error, isNull);
    harness.notifier.passwordFocused();
    expect(harness.state.phoneError, isFalse);
  });

  test('UI-07 leaving cancels login and ignores a late success', () async {
    final _ControllableAuthRepository repository = _ControllableAuthRepository(
      blockLogin: true,
    );
    final _LoginHarness harness = _LoginHarness(repository);
    addTearDown(harness.dispose);

    harness.notifier
      ..usernameChanged('13800138000')
      ..passwordChanged('secret');
    final Future<void> submit = harness.notifier.submit();
    await Future<void>.delayed(Duration.zero);
    expect(harness.state.submitting, isTrue);

    harness.notifier.cancel();
    await submit;
    repository.completeLogin(const DataSuccess<void>(null));
    await Future<void>.delayed(Duration.zero);

    expect(repository.cancellation?.isCancelled, isTrue);
    expect(harness.state.submitting, isFalse);
    expect(harness.state.completed, isFalse);
    expect(harness.state.password, isEmpty);
  });

  test('UI-07 restored authentication closes an idle login route', () {
    final _ControllableAuthRepository repository =
        _ControllableAuthRepository();
    final _LoginHarness harness = _LoginHarness(repository);
    addTearDown(harness.dispose);

    repository.setAuthenticated(true);

    expect(harness.state.completed, isTrue);
  });
}

class _LoginHarness {
  _LoginHarness(AuthRepository repository)
    : container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
      ) {
    subscription = container.listen<LoginUiState>(
      loginViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
  }

  final ProviderContainer container;
  late final ProviderSubscription<LoginUiState> subscription;

  LoginViewModel get notifier =>
      container.read(loginViewModelProvider.notifier);
  LoginUiState get state => container.read(loginViewModelProvider);

  void dispose() {
    subscription.close();
    container.dispose();
  }
}

class _ControllableAuthRepository extends ChangeNotifier
    implements AuthRepository {
  _ControllableAuthRepository({
    this.loginResult = const DataSuccess<void>(null),
    this.blockLogin = false,
  });

  final DataResult<void> loginResult;
  final bool blockLogin;
  final Completer<DataResult<void>> _loginCompleter =
      Completer<DataResult<void>>();
  int loginCalls = 0;
  RequestCancellation? cancellation;
  bool authenticated = false;

  void completeLogin(DataResult<void> result) {
    if (!_loginCompleter.isCompleted) _loginCompleter.complete(result);
  }

  void setAuthenticated(bool value) {
    authenticated = value;
    notifyListeners();
  }

  @override
  AuthStateView view() => AuthStateView(
    loading: false,
    authenticated: authenticated,
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
    loginCalls++;
    this.cancellation = cancellation;
    if (!blockLogin) return loginResult;
    return Future.any<DataResult<void>>(<Future<DataResult<void>>>[
      _loginCompleter.future,
      cancellation.whenCancelled.then<DataResult<void>>(
        (_) => throw const RequestCancelledException(),
      ),
    ]);
  }

  @override
  Future<DataResult<void>> restore() async => const DataSuccess<void>(null);

  @override
  Future<LogoutOutcome> logout() async =>
      LogoutOutcome(generation: 1, remote: const DataSuccess<void>(null));
}
