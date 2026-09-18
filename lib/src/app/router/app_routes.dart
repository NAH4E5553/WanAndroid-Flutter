import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wanandroid_flutter/src/app/router/app_shell.dart';
import 'package:wanandroid_flutter/src/app/router/branch_restoration_controller.dart';
import 'package:wanandroid_flutter/src/features/home/navigation/home_navigation.dart';
import 'package:wanandroid_flutter/src/features/profile/navigation/profile_navigation.dart';
import 'package:wanandroid_flutter/src/features/topics/navigation/topics_navigation.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

part 'app_routes.g.dart';

@TypedStatefulShellRoute<MainShellRouteData>(
  branches: <TypedStatefulShellBranch<StatefulShellBranchData>>[
    TypedStatefulShellBranch<HomeBranchData>(
      routes: <TypedRoute<RouteData>>[
        TypedGoRoute<HomeRouteData>(
          path: '/home',
          routes: <TypedRoute<RouteData>>[
            TypedGoRoute<HomePreviewRouteData>(path: 'preview/:articleId'),
          ],
        ),
      ],
    ),
    TypedStatefulShellBranch<TopicsBranchData>(
      routes: <TypedRoute<RouteData>>[
        TypedGoRoute<TopicsRouteData>(path: '/topics'),
      ],
    ),
    TypedStatefulShellBranch<ProfileBranchData>(
      routes: <TypedRoute<RouteData>>[
        TypedGoRoute<ProfileRouteData>(path: '/profile'),
      ],
    ),
  ],
)
class MainShellRouteData extends StatefulShellRouteData {
  const MainShellRouteData();

  static const String $restorationScopeId = 'main-shell';

  @override
  Widget builder(
    BuildContext context,
    GoRouterState state,
    StatefulNavigationShell navigationShell,
  ) => AppShell(navigationShell: navigationShell);
}

class HomeBranchData extends StatefulShellBranchData {
  const HomeBranchData();

  static const String $restorationScopeId = 'home-branch';
}

class TopicsBranchData extends StatefulShellBranchData {
  const TopicsBranchData();

  static const String $restorationScopeId = 'topics-branch';
}

class ProfileBranchData extends StatefulShellBranchData {
  const ProfileBranchData();

  static const String $restorationScopeId = 'profile-branch';
}

class HomeRouteData extends GoRouteData with $HomeRouteData {
  const HomeRouteData();

  @override
  Widget build(BuildContext context, GoRouterState state) => buildHomeScreen(
    onArticleTap: (Article article) {
      final BranchRestorationController controller = BranchRestorationScope.of(
        context,
      );
      final HomePreviewRouteData route = HomePreviewRouteData(
        articleId: article.id,
        routeInstanceId: controller.nextRouteInstanceId(),
        title: article.title,
      );
      controller.push(0, route.location);
      unawaited(route.push<void>(context));
    },
  );
}

class HomePreviewRouteData extends GoRouteData with $HomePreviewRouteData {
  const HomePreviewRouteData({
    required this.articleId,
    required this.routeInstanceId,
    required this.title,
  });

  final int articleId;
  final String routeInstanceId;
  final String title;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    final String location = this.location;
    final BranchRestorationController controller = BranchRestorationScope.of(
      context,
    );
    void recordPop() => controller.pop(0, location);
    return MaterialPage<void>(
      key: state.pageKey,
      restorationId: routeInstanceId,
      child: buildHomePreviewScreen(
        articleId: articleId,
        title: title,
        onBack: () {
          recordPop();
          context.pop();
        },
        onPopped: recordPop,
      ),
    );
  }
}

class TopicsRouteData extends GoRouteData with $TopicsRouteData {
  const TopicsRouteData();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      buildTopicsScreen();
}

class ProfileRouteData extends GoRouteData with $ProfileRouteData {
  const ProfileRouteData();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      buildProfileScreen();
}
