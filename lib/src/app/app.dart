import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wanandroid_flutter/src/app/router/app_router.dart';
import 'package:wanandroid_flutter/src/app/router/branch_restoration_controller.dart';
import 'package:wanandroid_flutter/src/core/navigation/branch_stack_snapshot.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';

class WanAndroidApp extends StatelessWidget {
  const WanAndroidApp({super.key});

  @override
  Widget build(BuildContext context) => const RootRestorationScope(
    restorationId: 'wanandroid-root',
    child: _RestorableWanAndroidApp(),
  );
}

class _RestorableWanAndroidApp extends StatefulWidget {
  const _RestorableWanAndroidApp();

  @override
  State<_RestorableWanAndroidApp> createState() =>
      _RestorableWanAndroidAppState();
}

class _RestorableWanAndroidAppState extends State<_RestorableWanAndroidApp>
    with RestorationMixin {
  late final AppRouter _appRouter;
  late final BranchRestorationController _branchController;
  late final RestorableBranchStackSnapshot _restorableSnapshot;
  bool _listening = false;

  @override
  String get restorationId => 'wanandroid-app-state';

  @override
  void initState() {
    super.initState();
    _appRouter = AppRouter();
    _branchController = BranchRestorationController();
    _restorableSnapshot = RestorableBranchStackSnapshot(
      BranchStackSnapshot.initial(),
    );
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
  Widget build(BuildContext context) => BranchRestorationScope(
    controller: _branchController,
    child: MaterialApp.router(
      title: 'WanAndroid Flutter',
      debugShowCheckedModeBanner: false,
      restorationScopeId: 'wanandroid-app',
      themeMode: ThemeMode.system,
      theme: wanTheme(brightness: Brightness.light),
      darkTheme: wanTheme(brightness: Brightness.dark),
      routerConfig: _appRouter.router,
    ),
  );

  @override
  void dispose() {
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
