import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';

final NotifierProvider<ThemeSettingsViewModel, ThemeSettingsUiState>
themeSettingsViewModelProvider =
    NotifierProvider.autoDispose<ThemeSettingsViewModel, ThemeSettingsUiState>(
      ThemeSettingsViewModel.new,
    );

class ThemeSettingsUiState {
  const ThemeSettingsUiState({
    required this.loadStatus,
    required this.palette,
    required this.mode,
    required this.saving,
    required this.saveFailed,
  });

  final ThemeLoadStatus loadStatus;
  final WanPalette palette;
  final ThemeMode mode;
  final bool saving;
  final bool saveFailed;

  bool get ready => loadStatus != ThemeLoadStatus.loading;
}

class ThemeSettingsViewModel extends Notifier<ThemeSettingsUiState> {
  late final ThemeController _controller;

  @override
  ThemeSettingsUiState build() {
    _controller = ref.read(themeControllerProvider);
    _controller.addListener(_publish);
    ref.onDispose(() => _controller.removeListener(_publish));
    return _snapshot();
  }

  Future<ThemeApplyResult> apply(WanPalette palette, ThemeMode mode) =>
      _controller.apply(palette, mode);

  void _publish() => state = _snapshot();

  ThemeSettingsUiState _snapshot() => ThemeSettingsUiState(
    loadStatus: _controller.loadStatus,
    palette: _controller.palette,
    mode: _controller.mode,
    saving: _controller.saving,
    saveFailed: _controller.saveFailed,
  );
}
