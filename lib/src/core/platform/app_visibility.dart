import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppVisibilityState {
  const AppVisibilityState({
    this.lifecycle = AppLifecycleState.resumed,
    this.activeBranch = 0,
    this.homeRouteCurrent = true,
  });

  final AppLifecycleState lifecycle;
  final int activeBranch;
  final bool homeRouteCurrent;

  bool get homeVisible =>
      lifecycle == AppLifecycleState.resumed &&
      activeBranch == 0 &&
      homeRouteCurrent;

  AppVisibilityState copyWith({
    AppLifecycleState? lifecycle,
    int? activeBranch,
    bool? homeRouteCurrent,
  }) => AppVisibilityState(
    lifecycle: lifecycle ?? this.lifecycle,
    activeBranch: activeBranch ?? this.activeBranch,
    homeRouteCurrent: homeRouteCurrent ?? this.homeRouteCurrent,
  );
}

final NotifierProvider<AppVisibilityController, AppVisibilityState>
appVisibilityProvider =
    NotifierProvider<AppVisibilityController, AppVisibilityState>(
      AppVisibilityController.new,
    );

class AppVisibilityController extends Notifier<AppVisibilityState> {
  @override
  AppVisibilityState build() => const AppVisibilityState();

  void updateRoute({
    required int activeBranch,
    required bool homeRouteCurrent,
  }) {
    if (state.activeBranch == activeBranch &&
        state.homeRouteCurrent == homeRouteCurrent) {
      return;
    }
    state = state.copyWith(
      activeBranch: activeBranch,
      homeRouteCurrent: homeRouteCurrent,
    );
  }

  void updateLifecycle(AppLifecycleState lifecycle) {
    if (state.lifecycle == lifecycle) return;
    state = state.copyWith(lifecycle: lifecycle);
  }
}
