import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wanandroid_flutter/src/app/router/app_shell.dart';
import 'package:wanandroid_flutter/src/app/router/branch_restoration_controller.dart';
import 'package:wanandroid_flutter/src/features/auth/navigation/auth_navigation.dart';
import 'package:wanandroid_flutter/src/features/home/navigation/home_navigation.dart';
import 'package:wanandroid_flutter/src/features/profile/navigation/profile_navigation.dart';
import 'package:wanandroid_flutter/src/features/reader/navigation/reader_navigation.dart';
import 'package:wanandroid_flutter/src/features/topics/navigation/topics_navigation.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

part 'app_routes.g.dart';

@TypedGoRoute<LoginRouteData>(path: '/login')
class LoginRouteData extends GoRouteData with $LoginRouteData {
  const LoginRouteData();

  @override
  Widget build(BuildContext context, GoRouterState state) => buildLoginScreen(
    onBack: () => context.pop(),
    onLoggedIn: () => context.pop(),
  );
}

@TypedStatefulShellRoute<MainShellRouteData>(
  branches: <TypedStatefulShellBranch<StatefulShellBranchData>>[
    TypedStatefulShellBranch<HomeBranchData>(
      routes: <TypedRoute<RouteData>>[
        TypedGoRoute<HomeRouteData>(
          path: '/home',
          routes: <TypedRoute<RouteData>>[
            TypedGoRoute<SearchRouteData>(path: 'search'),
            TypedGoRoute<DailyQuestionsRouteData>(path: 'questions'),
            TypedGoRoute<HomePreviewRouteData>(path: 'preview/:articleId'),
          ],
        ),
      ],
    ),
    TypedStatefulShellBranch<TopicsBranchData>(
      routes: <TypedRoute<RouteData>>[
        TypedGoRoute<TopicsRouteData>(
          path: '/topics',
          routes: <TypedRoute<RouteData>>[
            TypedGoRoute<TopicsPreviewRouteData>(path: 'preview/:articleId'),
          ],
        ),
      ],
    ),
    TypedStatefulShellBranch<ProfileBranchData>(
      routes: <TypedRoute<RouteData>>[
        TypedGoRoute<ProfileRouteData>(
          path: '/profile',
          routes: <TypedRoute<RouteData>>[
            TypedGoRoute<HistoryRouteData>(
              path: 'history',
              routes: [TypedGoRoute<HistoryReaderRouteData>(path: 'read')],
            ),
            TypedGoRoute<CollectionsRouteData>(
              path: 'collections',
              routes: [TypedGoRoute<CollectionsReaderRouteData>(path: 'read')],
            ),
            TypedGoRoute<ThemeSettingsRouteData>(path: 'theme'),
          ],
        ),
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
    onArticleTap: (Article article) => _pushArticle(context, article),
    onSearchTap: () {
      final BranchRestorationController controller = BranchRestorationScope.of(
        context,
      );
      final SearchRouteData route = SearchRouteData(
        routeInstanceId: controller.nextRouteInstanceId(),
      );
      controller.push(0, route.location);
      unawaited(route.push<void>(context));
    },
    onViewAllQuestions: () {
      final BranchRestorationController controller = BranchRestorationScope.of(
        context,
      );
      final DailyQuestionsRouteData route = DailyQuestionsRouteData(
        routeInstanceId: controller.nextRouteInstanceId(),
      );
      controller.push(0, route.location);
      unawaited(route.push<void>(context));
    },
  );
}

class SearchRouteData extends GoRouteData with $SearchRouteData {
  const SearchRouteData({required this.routeInstanceId});

  final String routeInstanceId;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _homeChildPage(
        context: context,
        state: state,
        restorationId: routeInstanceId,
        child: buildSearchScreen(
          routeInstanceId: routeInstanceId,
          onBack: () => _popHomeChild(context, location),
          onArticleTap: (Article article) => _pushArticle(context, article),
        ),
      );
}

class DailyQuestionsRouteData extends GoRouteData
    with $DailyQuestionsRouteData {
  const DailyQuestionsRouteData({required this.routeInstanceId});

  final String routeInstanceId;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) =>
      _homeChildPage(
        context: context,
        state: state,
        restorationId: routeInstanceId,
        child: buildDailyQuestionsScreen(
          routeInstanceId: routeInstanceId,
          onBack: () => _popHomeChild(context, location),
          onArticleTap: (Article article) => _pushArticle(context, article),
        ),
      );
}

class HomePreviewRouteData extends GoRouteData with $HomePreviewRouteData {
  const HomePreviewRouteData({
    required this.articleId,
    required this.routeInstanceId,
    required this.title,
    this.url = '',
  });

  final int articleId;
  final String routeInstanceId;
  final String title;
  final String url;

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
      child: buildArticleReaderScreen(
        articleId: articleId,
        title: title,
        url: url,
        onExit: () {
          recordPop();
          context.pop();
        },
        onPopped: recordPop,
        onLogin: () => unawaited(const LoginRouteData().push<void>(context)),
      ),
    );
  }
}

class TopicsRouteData extends GoRouteData with $TopicsRouteData {
  const TopicsRouteData();

  @override
  Widget build(BuildContext context, GoRouterState state) => buildTopicsScreen(
    onArticleTap: (Article article) {
      final BranchRestorationController controller = BranchRestorationScope.of(
        context,
      );
      final TopicsPreviewRouteData route = TopicsPreviewRouteData(
        articleId: article.id,
        routeInstanceId: controller.nextRouteInstanceId(),
        title: article.title,
        url: article.url,
      );
      controller.push(1, route.location);
      unawaited(route.push<void>(context));
    },
  );
}

class TopicsPreviewRouteData extends GoRouteData with $TopicsPreviewRouteData {
  const TopicsPreviewRouteData({
    required this.articleId,
    required this.routeInstanceId,
    required this.title,
    this.url = '',
  });

  final int articleId;
  final String routeInstanceId;
  final String title;
  final String url;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    final String location = this.location;
    final BranchRestorationController controller = BranchRestorationScope.of(
      context,
    );
    void recordPop() => controller.pop(1, location);
    return MaterialPage<void>(
      key: state.pageKey,
      restorationId: routeInstanceId,
      child: buildArticleReaderScreen(
        articleId: articleId,
        title: title,
        url: url,
        onExit: () {
          recordPop();
          context.pop();
        },
        onPopped: recordPop,
        onLogin: () => unawaited(const LoginRouteData().push<void>(context)),
      ),
    );
  }
}

class ProfileRouteData extends GoRouteData with $ProfileRouteData {
  const ProfileRouteData();

  @override
  Widget build(BuildContext context, GoRouterState state) => buildProfileScreen(
    onHistoryTap: () {
      final controller = BranchRestorationScope.of(context);
      final route = HistoryRouteData(
        routeInstanceId: controller.nextRouteInstanceId(),
      );
      controller.push(2, route.location);
      unawaited(route.push<void>(context));
    },
    onCollectionsTap: () {
      final controller = BranchRestorationScope.of(context);
      final route = CollectionsRouteData(
        routeInstanceId: controller.nextRouteInstanceId(),
      );
      controller.push(2, route.location);
      unawaited(route.push<void>(context));
    },
    onThemeTap: () {
      final controller = BranchRestorationScope.of(context);
      final route = ThemeSettingsRouteData(
        routeInstanceId: controller.nextRouteInstanceId(),
      );
      controller.push(2, route.location);
      unawaited(route.push<void>(context));
    },
    onLoginTap: () => unawaited(const LoginRouteData().push<void>(context)),
  );
}

class CollectionsRouteData extends GoRouteData with $CollectionsRouteData {
  const CollectionsRouteData({required this.routeInstanceId});

  final String routeInstanceId;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    final controller = BranchRestorationScope.of(context);
    final currentLocation = location;
    void recordPop() => controller.pop(2, currentLocation);
    return MaterialPage<void>(
      key: state.pageKey,
      restorationId: routeInstanceId,
      child: buildCollectionsScreen(
        onBack: () {
          recordPop();
          context.pop();
        },
        onLoginTap: () => unawaited(const LoginRouteData().push<void>(context)),
        onArticleTap: (String url, String title, int? articleId) {
          final route = CollectionsReaderRouteData(
            routeInstanceId: controller.nextRouteInstanceId(),
            url: url,
            title: title,
            articleId: articleId,
          );
          controller.push(2, route.location);
          unawaited(route.push<void>(context));
        },
      ),
    );
  }
}

class CollectionsReaderRouteData extends GoRouteData
    with $CollectionsReaderRouteData {
  const CollectionsReaderRouteData({
    required this.routeInstanceId,
    required this.url,
    required this.title,
    this.articleId,
  });

  final String routeInstanceId;
  final String url;
  final String title;
  final int? articleId;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    final controller = BranchRestorationScope.of(context);
    final currentLocation = location;
    void recordPop() => controller.pop(2, currentLocation);
    return MaterialPage<void>(
      key: state.pageKey,
      restorationId: routeInstanceId,
      child: buildArticleReaderScreen(
        articleId: articleId,
        title: title,
        url: url,
        onExit: () {
          recordPop();
          context.pop();
        },
        onPopped: recordPop,
        onLogin: () => unawaited(const LoginRouteData().push<void>(context)),
      ),
    );
  }
}

class ThemeSettingsRouteData extends GoRouteData with $ThemeSettingsRouteData {
  const ThemeSettingsRouteData({required this.routeInstanceId});

  final String routeInstanceId;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    final controller = BranchRestorationScope.of(context);
    final currentLocation = location;
    void recordPop() => controller.pop(2, currentLocation);
    return MaterialPage<void>(
      key: state.pageKey,
      restorationId: routeInstanceId,
      child: buildThemeSettingsScreen(
        onBack: () {
          recordPop();
          context.pop();
        },
      ),
    );
  }
}

class HistoryRouteData extends GoRouteData with $HistoryRouteData {
  const HistoryRouteData({required this.routeInstanceId});

  final String routeInstanceId;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    final controller = BranchRestorationScope.of(context);
    final currentLocation = location;
    void recordPop() => controller.pop(2, currentLocation);
    return MaterialPage<void>(
      key: state.pageKey,
      restorationId: routeInstanceId,
      child: buildReadingHistoryScreen(
        onBack: () {
          recordPop();
          context.pop();
        },
        onPopped: recordPop,
        onRead: (String url, String title, int? articleId) {
          final route = HistoryReaderRouteData(
            routeInstanceId: controller.nextRouteInstanceId(),
            url: url,
            title: title,
            articleId: articleId,
          );
          controller.push(2, route.location);
          unawaited(route.push<void>(context));
        },
      ),
    );
  }
}

class HistoryReaderRouteData extends GoRouteData with $HistoryReaderRouteData {
  const HistoryReaderRouteData({
    required this.routeInstanceId,
    required this.url,
    required this.title,
    this.articleId,
  });

  final String routeInstanceId;
  final String url;
  final String title;
  final int? articleId;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    final controller = BranchRestorationScope.of(context);
    final currentLocation = location;
    void recordPop() => controller.pop(2, currentLocation);
    return MaterialPage<void>(
      key: state.pageKey,
      restorationId: routeInstanceId,
      child: buildArticleReaderScreen(
        articleId: articleId,
        title: title,
        url: url,
        onExit: () {
          recordPop();
          context.pop();
        },
        onPopped: recordPop,
        onLogin: () => unawaited(const LoginRouteData().push<void>(context)),
      ),
    );
  }
}

void _pushArticle(BuildContext context, Article article) {
  final BranchRestorationController controller = BranchRestorationScope.of(
    context,
  );
  final HomePreviewRouteData route = HomePreviewRouteData(
    articleId: article.id,
    routeInstanceId: controller.nextRouteInstanceId(),
    title: article.title,
    url: article.url,
  );
  controller.push(0, route.location);
  unawaited(route.push<void>(context));
}

void _popHomeChild(BuildContext context, String location) {
  BranchRestorationScope.of(context).pop(0, location);
  context.pop();
}

Page<void> _homeChildPage({
  required BuildContext context,
  required GoRouterState state,
  required String restorationId,
  required Widget child,
}) => MaterialPage<void>(
  key: state.pageKey,
  restorationId: restorationId,
  child: PopScope<void>(
    onPopInvokedWithResult: (bool didPop, void result) {
      if (didPop) {
        BranchRestorationScope.of(context).pop(0, state.uri.toString());
      }
    },
    child: child,
  ),
);
