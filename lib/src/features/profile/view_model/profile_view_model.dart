import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';

final NotifierProvider<ProfileViewModel, ProfileUiState>
profileViewModelProvider = NotifierProvider<ProfileViewModel, ProfileUiState>(
  ProfileViewModel.new,
);

class ProfileUiState {
  const ProfileUiState({
    required this.auth,
    required this.palette,
    required this.mode,
    this.loggingOut = false,
    this.logoutNotice,
  });

  final AuthStateView auth;
  final WanPalette palette;
  final ThemeMode mode;
  final bool loggingOut;
  final String? logoutNotice;

  ProfileUiState copyWith({
    AuthStateView? auth,
    WanPalette? palette,
    ThemeMode? mode,
    bool? loggingOut,
    String? logoutNotice,
    bool clearLogoutNotice = false,
  }) => ProfileUiState(
    auth: auth ?? this.auth,
    palette: palette ?? this.palette,
    mode: mode ?? this.mode,
    loggingOut: loggingOut ?? this.loggingOut,
    logoutNotice: clearLogoutNotice ? null : logoutNotice ?? this.logoutNotice,
  );
}

class ProfileViewModel extends Notifier<ProfileUiState> {
  late final AuthRepository _authRepository;
  late final ThemeController _themeController;
  bool _active = true;

  @override
  ProfileUiState build() {
    _active = true;
    _authRepository = ref.read(authRepositoryProvider);
    _themeController = ref.read(themeControllerProvider);
    _authRepository.addListener(_publishAuth);
    _themeController.addListener(_publishTheme);
    ref.onDispose(() {
      _active = false;
      _authRepository.removeListener(_publishAuth);
      _themeController.removeListener(_publishTheme);
    });
    return ProfileUiState(
      auth: _authRepository.view(),
      palette: _themeController.palette,
      mode: _themeController.mode,
    );
  }

  Future<void> logout() async {
    if (state.loggingOut) return;
    state = state.copyWith(loggingOut: true, clearLogoutNotice: true);
    final LogoutOutcome outcome = await _authRepository.logout();
    if (!_active) return;
    state = state.copyWith(
      auth: _authRepository.view(),
      loggingOut: false,
      logoutNotice: outcome.localDetached && outcome.remote is DataFailure<void>
          ? '本机已退出，服务器退出未确认。'
          : null,
      clearLogoutNotice:
          !(outcome.localDetached && outcome.remote is DataFailure<void>),
    );
  }

  void _publishAuth() {
    if (_active) state = state.copyWith(auth: _authRepository.view());
  }

  void _publishTheme() {
    if (!_active) return;
    state = state.copyWith(
      palette: _themeController.palette,
      mode: _themeController.mode,
    );
  }
}
