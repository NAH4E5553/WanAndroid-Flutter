import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/features/auth/state/login_ui_state.dart';
import 'package:wanandroid_flutter/src/features/auth/view/login_screen.dart';
import 'package:wanandroid_flutter/src/features/auth/view_model/login_view_model.dart';

Widget buildLoginScreen({
  required VoidCallback onBack,
  required VoidCallback onLoggedIn,
}) => _LoginRouteView(onBack: onBack, onLoggedIn: onLoggedIn);

class _LoginRouteView extends ConsumerStatefulWidget {
  const _LoginRouteView({required this.onBack, required this.onLoggedIn});

  final VoidCallback onBack;
  final VoidCallback onLoggedIn;

  @override
  ConsumerState<_LoginRouteView> createState() => _LoginRouteViewState();
}

class _LoginRouteViewState extends ConsumerState<_LoginRouteView> {
  bool _leaving = false;
  bool _completionScheduled = false;

  void _back() {
    if (_leaving) return;
    _leaving = true;
    ref.read(loginViewModelProvider.notifier).cancel();
    widget.onBack();
  }

  void _scheduleCompletion(LoginUiState state) {
    if (!state.completed || _completionScheduled || _leaving) return;
    _completionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _leaving) return;
      _leaving = true;
      widget.onLoggedIn();
    });
  }

  @override
  Widget build(BuildContext context) {
    final LoginUiState state = ref.watch(loginViewModelProvider);
    final LoginViewModel viewModel = ref.read(loginViewModelProvider.notifier);
    _scheduleCompletion(state);
    return PopScope<void>(
      // Keep Cupertino's native back-swipe available. A completed platform
      // pop still cancels the route-scoped request before disposal finishes.
      canPop: true,
      onPopInvokedWithResult: (bool didPop, void result) {
        if (!didPop) {
          _back();
        } else if (!_leaving) {
          _leaving = true;
          viewModel.cancel();
        }
      },
      child: LoginScreen(
        state: state,
        onUsernameChanged: viewModel.usernameChanged,
        onPasswordChanged: viewModel.passwordChanged,
        onPasswordFocused: viewModel.passwordFocused,
        onSubmit: viewModel.submit,
        onBack: _back,
      ),
    );
  }
}
