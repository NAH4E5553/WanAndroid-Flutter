// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_routes.dart';

// **************************************************************************
// GoRouterGenerator
// **************************************************************************

List<RouteBase> get $appRoutes => [$mainShellRouteData];

RouteBase get $mainShellRouteData => StatefulShellRouteData.$route(
  restorationScopeId: MainShellRouteData.$restorationScopeId,
  factory: $MainShellRouteDataExtension._fromState,
  branches: [
    StatefulShellBranchData.$branch(
      restorationScopeId: HomeBranchData.$restorationScopeId,
      routes: [
        GoRouteData.$route(
          path: '/home',
          hasOverriddenOnExit: false,
          factory: $HomeRouteData._fromState,
          routes: [
            GoRouteData.$route(
              path: 'search',
              hasOverriddenOnExit: false,
              factory: $SearchRouteData._fromState,
            ),
            GoRouteData.$route(
              path: 'questions',
              hasOverriddenOnExit: false,
              factory: $DailyQuestionsRouteData._fromState,
            ),
            GoRouteData.$route(
              path: 'preview/:articleId',
              hasOverriddenOnExit: false,
              factory: $HomePreviewRouteData._fromState,
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranchData.$branch(
      restorationScopeId: TopicsBranchData.$restorationScopeId,
      routes: [
        GoRouteData.$route(
          path: '/topics',
          hasOverriddenOnExit: false,
          factory: $TopicsRouteData._fromState,
          routes: [
            GoRouteData.$route(
              path: 'preview/:articleId',
              hasOverriddenOnExit: false,
              factory: $TopicsPreviewRouteData._fromState,
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranchData.$branch(
      restorationScopeId: ProfileBranchData.$restorationScopeId,
      routes: [
        GoRouteData.$route(
          path: '/profile',
          hasOverriddenOnExit: false,
          factory: $ProfileRouteData._fromState,
        ),
      ],
    ),
  ],
);

extension $MainShellRouteDataExtension on MainShellRouteData {
  static MainShellRouteData _fromState(GoRouterState state) =>
      const MainShellRouteData();
}

mixin $HomeRouteData on GoRouteData {
  static HomeRouteData _fromState(GoRouterState state) => const HomeRouteData();

  @override
  String get location => GoRouteData.$location('/home');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $SearchRouteData on GoRouteData {
  static SearchRouteData _fromState(GoRouterState state) => SearchRouteData(
    routeInstanceId: state.uri.queryParameters['route-instance-id']!,
  );

  SearchRouteData get _self => this as SearchRouteData;

  @override
  String get location => GoRouteData.$location(
    '/home/search',
    queryParams: {'route-instance-id': _self.routeInstanceId},
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $DailyQuestionsRouteData on GoRouteData {
  static DailyQuestionsRouteData _fromState(GoRouterState state) =>
      DailyQuestionsRouteData(
        routeInstanceId: state.uri.queryParameters['route-instance-id']!,
      );

  DailyQuestionsRouteData get _self => this as DailyQuestionsRouteData;

  @override
  String get location => GoRouteData.$location(
    '/home/questions',
    queryParams: {'route-instance-id': _self.routeInstanceId},
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $HomePreviewRouteData on GoRouteData {
  static HomePreviewRouteData _fromState(GoRouterState state) =>
      HomePreviewRouteData(
        articleId: int.parse(state.pathParameters['articleId']!),
        routeInstanceId: state.uri.queryParameters['route-instance-id']!,
        title: state.uri.queryParameters['title']!,
      );

  HomePreviewRouteData get _self => this as HomePreviewRouteData;

  @override
  String get location => GoRouteData.$location(
    '/home/preview/${Uri.encodeComponent(_self.articleId.toString())}',
    queryParams: {
      'route-instance-id': _self.routeInstanceId,
      'title': _self.title,
    },
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $TopicsRouteData on GoRouteData {
  static TopicsRouteData _fromState(GoRouterState state) =>
      const TopicsRouteData();

  @override
  String get location => GoRouteData.$location('/topics');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $TopicsPreviewRouteData on GoRouteData {
  static TopicsPreviewRouteData _fromState(GoRouterState state) =>
      TopicsPreviewRouteData(
        articleId: int.parse(state.pathParameters['articleId']!),
        routeInstanceId: state.uri.queryParameters['route-instance-id']!,
        title: state.uri.queryParameters['title']!,
      );

  TopicsPreviewRouteData get _self => this as TopicsPreviewRouteData;

  @override
  String get location => GoRouteData.$location(
    '/topics/preview/${Uri.encodeComponent(_self.articleId.toString())}',
    queryParams: {
      'route-instance-id': _self.routeInstanceId,
      'title': _self.title,
    },
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $ProfileRouteData on GoRouteData {
  static ProfileRouteData _fromState(GoRouterState state) =>
      const ProfileRouteData();

  @override
  String get location => GoRouteData.$location('/profile');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}
