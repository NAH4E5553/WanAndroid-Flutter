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
    // 组装接线发生在首帧之后:在这里触碰 provider 会在首次绘制之前
    // 急切地初始化 home 依赖图(连同其请求)。
    // covered 判定本身默认取 core 控制器的静态答案,
    // 因此即使在本段代码运行之前,
    // 帧门控也是正确的。
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        _assembleStartupReveal();
      }
    });
  }

  /// 仅为启动揭幕做组装接线:home ViewModel 的遮挡判定取自权威控制器;
  /// 当层消失后,当前 home 快照会被重新上报,
  /// 从而让真正首次可见的帧完成启动计时点。
  /// Feature 代码绝不读取
  /// app 层控制器本身。
  void _assembleStartupReveal() {
    _startupRevealController = ref.read(startupRevealControllerProvider);
    ref.read(homeViewModelProvider.notifier).startupCovered = () =>
        !(_startupRevealController?.isDone ?? true);
    _startupRevealController!.addListener(_onStartupRevealChanged);
    // 生产快速路径:一旦可见的 home 到达终态(成功/空/错误已在层后渲染),
    // 揭幕即提前结束,而不播放完整预告。请求仍在并行运行;
    // 失败/空态绝不阻塞
    //(遮挡时长由看门狗限定)。
    ref.listenManual(homeViewModelProvider, (
      HomeUiState? previous,
      HomeUiState next,
    ) {
      _forwardReadiness(next);
    });
    // 本段接线运行时 home 依赖图可能已处于终态(快速构建、预加载状态)——
    // 因此立即检查一次,而不是等待状态变化。
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
      // 推迟到 post-frame 回调执行:在这轮通知迭代内部修改另一个 provider
      // 是不安全的。重新发布的快照会让 home 屏幕在
      // 下一帧重建——那是内容真正首次可见的一帧——
      // 并且该次构建会在自己的构建窗口内
      // 上报其启动计时点。
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
