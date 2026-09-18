import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:wanandroid_flutter/src/app/router/app_routes.dart';
import 'package:wanandroid_flutter/src/core/navigation/branch_stack_snapshot.dart';

class AppRouter {
  AppRouter()
    : router = GoRouter(
        routes: $appRoutes,
        initialLocation: const HomeRouteData().location,
        restorationScopeId: 'app-router',
      );

  final GoRouter router;

  Future<void> restoreBranchStacks(BranchStackSnapshot snapshot) async {
    final List<int> order = <int>[
      for (int index = 0; index < snapshot.stacks.length; index += 1)
        if (index != snapshot.activeBranch) index,
      snapshot.activeBranch,
    ];
    for (final int branch in order) {
      final List<String> stack = snapshot.stacks[branch];
      router.go(stack.first);
      await _nextFrame();
      for (final String location in stack.skip(1)) {
        unawaited(router.push<void>(location));
        await _nextFrame();
      }
    }
  }

  void dispose() => router.dispose();

  Future<void> _nextFrame() {
    final Completer<void> completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      completer.complete();
    });
    SchedulerBinding.instance.scheduleFrame();
    return completer.future;
  }
}
