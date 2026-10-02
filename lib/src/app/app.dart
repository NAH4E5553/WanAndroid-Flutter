import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/app/router/app_router.dart';
import 'package:wanandroid_flutter/src/app/router/app_routes.dart';
import 'package:wanandroid_flutter/src/app/router/branch_restoration_controller.dart';
import 'package:wanandroid_flutter/src/app/startup/startup_reveal_layer.dart';
import 'package:wanandroid_flutter/src/core/navigation/branch_stack_snapshot.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/startup/startup_reveal_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/avatar_repository.dart';
import 'package:wanandroid_flutter/src/features/home/state/home_ui_state.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_view_model.dart';

class WanAndroidApp extends StatelessWidget {
  const WanAndroidApp({super.key});

  @override
  Widget build(BuildContext context) => const RootRestorationScope(
    restorationId: 'wanandroid-root',
    child: _RestorableWanAndroidApp(),
  );
}

class _RestorableWanAndroidApp extends ConsumerStatefulWidget {
  const _RestorableWanAndroidApp();

  @override
  ConsumerState<_RestorableWanAndroidApp> createState() =>
      _RestorableWanAndroidAppState();
}

class _RestorableWanAndroidAppState
    extends ConsumerState<_RestorableWanAndroidApp>
    with RestorationMixin {
  late final AppRouter _appRouter;
  late final BranchRestorationController _branchController;
  late final RestorableBranchStackSnapshot _restorableSnapshot;
  bool _listening = false;

  @override
  String get restorationId => 'wanandroid-app-state';

  AvatarRepository? _avatarRepository;
  StartupRevealController? _startupRevealController;

  @override
  void initState() {
    super.initState();
    _appRouter = AppRouter();
    _branchController = BranchRestorationController();
    _restorableSnapshot = RestorableBranchStackSnapshot(
      BranchStackSnapshot.initial(),
    );
    // 进程恢复：仓储完成归属校验（recoveryReady）后导航到调整页。
    _avatarRepository = ref.read(avatarRepositoryProvider);
    _avatarRepository!.addListener(_navigateToRecoveredAvatar);
    if (_avatarRepository!.view().recoveryReady) {
      _navigateToRecoveredAvatar();
    }
    // Composition wiring happens after the first frame: touching providers
    // here would eagerly initialize the home graph (and its requests) before
    // the first paint. The covered predicate itself defaults to the core
    // controller's static answer, so the frame gate is correct even before
    // this runs.
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        _assembleStartupReveal();
      }
    });
  }

  /// Composition-only wiring for the startup reveal: the home ViewModel gets
  /// its occlusion predicate from the authoritative controller, and once the
  /// layer is gone the current home snapshot is re-reported so the genuine
  /// first visible frame can complete the startup points. Feature code never
  /// reads the app-layer controller itself.
  void _assembleStartupReveal() {
    _startupRevealController = ref.read(startupRevealControllerProvider);
    ref.read(homeViewModelProvider.notifier).startupCovered = () =>
        !(_startupRevealController?.isDone ?? true);
    _startupRevealController!.addListener(_onStartupRevealChanged);
    // Production fast-path: as soon as the visible home reaches its terminal
    // state (success/empty/error rendered behind the layer), the reveal ends
    // early instead of playing the full teaser. Requests still run in
    // parallel; failure/empty never block (the watchdog bounds occlusion).
    ref.listenManual(homeViewModelProvider, (
      HomeUiState? previous,
      HomeUiState next,
    ) {
      _forwardReadiness(next);
    });
    // The home graph may already be terminal when this wiring runs (fast
    // builds, preloaded states) — check once instead of waiting for a change.
    _forwardReadiness(ref.read(homeViewModelProvider));
  }

  void _forwardReadiness(HomeUiState state) {
    final bool ready =
        !state.articles.isInitialLoading && !state.questions.loading;
    if (ready) {
      _startupRevealController?.markContentReady();
    }
  }

  void _onStartupRevealChanged() {
    final StartupRevealController? controller = _startupRevealController;
    if (controller == null) {
      return;
    }
    if (controller.isDone) {
      // Deferred to a post-frame callback: mutating another provider from
      // inside this notification iteration is unsafe. The republished
      // snapshot makes the home screen rebuild on the NEXT frame — the first
      // frame where the content is genuinely visible — and that build
      // reports its startup points inside its own build window.
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (!mounted) {
          return;
        }
        ref.read(homeViewModelProvider.notifier).republish();
      });
      return;
    }
    ref.read(homeViewModelProvider.notifier).startupCovered = () =>
        !controller.isDone;
  }

  void _navigateToRecoveredAvatar() {
    if (!mounted || !_avatarRepository!.view().recoveryReady) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || !_avatarRepository!.view().recoveryReady) {
        return;
      }
      final String location = AvatarAdjustRouteData(
        routeInstanceId: _branchController.nextRouteInstanceId(),
      ).location;
      _branchController.push(2, location);
      unawaited(_appRouter.router.push(location));
      // 导航已接管恢复候选；由调整页的既有取消/完成流程收尾。
      _avatarRepository!.markRecoveryConsumed();
    });
  }

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_restorableSnapshot, 'branch-stacks');
    _branchController.replace(_restorableSnapshot.value);
    if (!_listening) {
      _branchController.addListener(_saveSnapshot);
      _listening = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        unawaited(_appRouter.restoreBranchStacks(_branchController.snapshot));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeController theme = ref.watch(themeControllerProvider);
    return BranchRestorationScope(
      controller: _branchController,
      child: AnimatedBuilder(
        animation: theme,
        builder: (BuildContext context, Widget? child) => MaterialApp.router(
          title: 'WanAndroid Flutter',
          debugShowCheckedModeBanner: false,
          restorationScopeId: 'wanandroid-app',
          themeMode: theme.mode,
          theme: wanTheme(palette: theme.palette, brightness: Brightness.light),
          darkTheme: wanTheme(
            palette: theme.palette,
            brightness: Brightness.dark,
          ),
          builder: (BuildContext context, Widget? child) =>
              StartupRevealLayer(child: child ?? const SizedBox.shrink()),
          routerConfig: _appRouter.router,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _avatarRepository?.removeListener(_navigateToRecoveredAvatar);
    _startupRevealController?.removeListener(_onStartupRevealChanged);
    if (_listening) {
      _branchController.removeListener(_saveSnapshot);
    }
    _restorableSnapshot.dispose();
    _branchController.dispose();
    _appRouter.dispose();
    super.dispose();
  }

  void _saveSnapshot() {
    _restorableSnapshot.value = _branchController.snapshot;
  }
}
