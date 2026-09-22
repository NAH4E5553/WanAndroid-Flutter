import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/features/auth/policy/phone_number_policy.dart';

class LoginUiState {
  const LoginUiState({
    this.username = '',
    this.password = '',
    this.submitting = false,
    this.completed = false,
    this.phoneError = false,
    this.error,
  });

  final String username;
  final String password;
  final bool submitting;
  final bool completed;
  final bool phoneError;
  final DataError? error;

  bool get canSubmit =>
      !submitting &&
      !completed &&
      isMainlandMobileNumber(username) &&
      password.isNotEmpty;

  LoginUiState copyWith({
    String? username,
    String? password,
    bool? submitting,
    bool? completed,
    bool? phoneError,
    DataError? error,
    bool clearError = false,
  }) => LoginUiState(
    username: username ?? this.username,
    password: password ?? this.password,
    submitting: submitting ?? this.submitting,
    completed: completed ?? this.completed,
    phoneError: phoneError ?? this.phoneError,
    error: clearError ? null : error ?? this.error,
  );
}
