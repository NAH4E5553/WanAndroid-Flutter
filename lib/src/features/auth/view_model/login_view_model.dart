import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/features/auth/policy/phone_number_policy.dart';
import 'package:wanandroid_flutter/src/features/auth/state/login_ui_state.dart';

final loginViewModelProvider =
    NotifierProvider.autoDispose<LoginViewModel, LoginUiState>(
      LoginViewModel.new,
    );

class LoginViewModel extends Notifier<LoginUiState> {
  late final AuthRepository _repository;
  DefaultRequestCancellationController? _cancellation;
  int _requestGeneration = 0;

  @override
  LoginUiState build() {
    _repository = ref.read(authRepositoryProvider);
    _repository.addListener(_onSessionChanged);
    ref.onDispose(() {
      _requestGeneration++;
      _cancellation?.cancel();
      _repository.removeListener(_onSessionChanged);
    });
    return LoginUiState(completed: _repository.view().authenticated);
  }

  void usernameChanged(String value) {
    if (state.submitting || state.completed) return;
    state = state.copyWith(
      username: _bounded(value),
      phoneError: false,
      clearError: true,
    );
  }

  void passwordChanged(String value) {
    if (state.submitting || state.completed) return;
    state = state.copyWith(password: _bounded(value), clearError: true);
  }

  void passwordFocused() {
    if (state.submitting || state.completed) return;
    state = state.copyWith(
      phoneError:
          state.username.isNotEmpty && !isMainlandMobileNumber(state.username),
    );
  }

  Future<void> submit() async {
    if (state.submitting || state.completed) return;
    if (!isMainlandMobileNumber(state.username)) {
      state = state.copyWith(phoneError: true);
      return;
    }
    if (!state.canSubmit) return;

    final int generation = ++_requestGeneration;
    final DefaultRequestCancellationController cancellation =
        DefaultRequestCancellationController();
    _cancellation = cancellation;
    state = state.copyWith(submitting: true, clearError: true);
    try {
      final DataResult<void> result = await _repository.login(
        state.username.trim(),
        state.password,
        cancellation: cancellation.signal,
      );
      cancellation.throwIfCancelled();
      if (generation != _requestGeneration) return;
      state = switch (result) {
        DataSuccess<void>() => state.copyWith(
          password: '',
          submitting: false,
          completed: true,
          clearError: true,
        ),
        DataFailure<void>(:final DataError error) => state.copyWith(
          submitting: false,
          error: error,
        ),
      };
    } on RequestCancelledException {
      if (generation == _requestGeneration) {
        state = state.copyWith(
          password: '',
          submitting: false,
          clearError: true,
        );
      }
    } finally {
      if (identical(_cancellation, cancellation)) {
        _cancellation = null;
      }
    }
  }

  void cancel() {
    _requestGeneration++;
    _cancellation?.cancel();
    _cancellation = null;
    state = state.copyWith(password: '', submitting: false, clearError: true);
  }

  void _onSessionChanged() {
    if (_repository.view().authenticated &&
        !state.submitting &&
        !state.completed) {
      state = state.copyWith(password: '', completed: true, clearError: true);
    }
  }

  String _bounded(String value) =>
      value.length <= 200 ? value : value.substring(0, 200);
}
