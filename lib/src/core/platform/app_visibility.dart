import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppVisibilityState {
  const AppVisibilityState({
    this.lifecycle = AppLifecycleState.resumed,
    this.activeBranch = 0,
    this.homeRouteCurrent = true,
    this.topicsRouteCurrent = false,
  });

  final AppLifecycleState lifecycle;
  final int activeBranch;
  final bool homeRouteCurrent;
  final bool topicsRouteCurrent;

  bool get homeVisible =>
      lifecycle == AppLifecycleState.resumed &&
      activeBranch == 0 &&
      homeRouteCurrent;

  bool get topicsVisible =>
      lifecycle == AppLifecycleState.resumed &&
      activeBranch == 1 &&
      topicsRouteCurrent;

  AppVisibilityState copyWith({
    AppLifecycleState? lifecycle,
    int? activeBranch,
    bool? homeRouteCurrent,
    bool? topicsRouteCurrent,
  }) => AppVisibilityState(
    lifecycle: lifecycle ?? this.lifecycle,
    activeBranch: activeBranch ?? this.activeBranch,
    homeRouteCurrent: homeRouteCurrent ?? this.homeRouteCurrent,
    topicsRouteCurrent: topicsRouteCurrent ?? this.topicsRouteCurrent,
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
    required bool topicsRouteCurrent,
  }) {
    if (state.activeBranch == activeBranch &&
        state.homeRouteCurrent == homeRouteCurrent &&
        state.topicsRouteCurrent == topicsRouteCurrent) {
      return;
    }
    state = state.copyWith(
      activeBranch: activeBranch,
      homeRouteCurrent: homeRouteCurrent,
      topicsRouteCurrent: topicsRouteCurrent,
    );
  }

  void updateLifecycle(AppLifecycleState lifecycle) {
    if (state.lifecycle == lifecycle) return;
    state = state.copyWith(lifecycle: lifecycle);
  }
}
