// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_routes.dart';

// **************************************************************************
// GoRouterGenerator
// **************************************************************************

List<RouteBase> get $appRoutes => [$loginRouteData, $mainShellRouteData];

RouteBase get $loginRouteData => GoRouteData.$route(
  path: '/login',
  hasOverriddenOnExit: false,
  factory: $LoginRouteData._fromState,
);

mixin $LoginRouteData on GoRouteData {
  static LoginRouteData _fromState(GoRouterState state) =>
      const LoginRouteData();

  @override
  String get location => GoRouteData.$location('/login');

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
          routes: [
            GoRouteData.$route(
              path: 'history',
              hasOverriddenOnExit: false,
              factory: $HistoryRouteData._fromState,
              routes: [
                GoRouteData.$route(
                  path: 'read',
                  hasOverriddenOnExit: false,
                  factory: $HistoryReaderRouteData._fromState,
                ),
              ],
            ),
            GoRouteData.$route(
              path: 'collections',
              hasOverriddenOnExit: false,
              factory: $CollectionsRouteData._fromState,
              routes: [
                GoRouteData.$route(
                  path: 'read',
                  hasOverriddenOnExit: false,
                  factory: $CollectionsReaderRouteData._fromState,
                ),
              ],
            ),
            GoRouteData.$route(
              path: 'theme',
              hasOverriddenOnExit: false,
              factory: $ThemeSettingsRouteData._fromState,
            ),
          ],
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
        url: state.uri.queryParameters['url'] ?? '',
      );

  HomePreviewRouteData get _self => this as HomePreviewRouteData;

  @override
  String get location => GoRouteData.$location(
    '/home/preview/${Uri.encodeComponent(_self.articleId.toString())}',
    queryParams: {
      'route-instance-id': _self.routeInstanceId,
      'title': _self.title,
      if (_self.url != '') 'url': _self.url,
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
        url: state.uri.queryParameters['url'] ?? '',
      );

  TopicsPreviewRouteData get _self => this as TopicsPreviewRouteData;

  @override
  String get location => GoRouteData.$location(
    '/topics/preview/${Uri.encodeComponent(_self.articleId.toString())}',
    queryParams: {
      'route-instance-id': _self.routeInstanceId,
      'title': _self.title,
      if (_self.url != '') 'url': _self.url,
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

mixin $HistoryRouteData on GoRouteData {
  static HistoryRouteData _fromState(GoRouterState state) => HistoryRouteData(
    routeInstanceId: state.uri.queryParameters['route-instance-id']!,
  );

  HistoryRouteData get _self => this as HistoryRouteData;

  @override
  String get location => GoRouteData.$location(
    '/profile/history',
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

mixin $HistoryReaderRouteData on GoRouteData {
  static HistoryReaderRouteData _fromState(GoRouterState state) =>
      HistoryReaderRouteData(
        routeInstanceId: state.uri.queryParameters['route-instance-id']!,
        url: state.uri.queryParameters['url']!,
        title: state.uri.queryParameters['title']!,
        articleId: _$convertMapValue(
          'article-id',
          state.uri.queryParameters,
          int.tryParse,
        ),
      );

  HistoryReaderRouteData get _self => this as HistoryReaderRouteData;

  @override
  String get location => GoRouteData.$location(
    '/profile/history/read',
    queryParams: {
      'route-instance-id': _self.routeInstanceId,
      'url': _self.url,
      'title': _self.title,
      if (_self.articleId != null) 'article-id': _self.articleId!.toString(),
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

mixin $CollectionsRouteData on GoRouteData {
  static CollectionsRouteData _fromState(GoRouterState state) =>
      CollectionsRouteData(
        routeInstanceId: state.uri.queryParameters['route-instance-id']!,
      );

  CollectionsRouteData get _self => this as CollectionsRouteData;

  @override
  String get location => GoRouteData.$location(
    '/profile/collections',
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

mixin $CollectionsReaderRouteData on GoRouteData {
  static CollectionsReaderRouteData _fromState(GoRouterState state) =>
      CollectionsReaderRouteData(
        routeInstanceId: state.uri.queryParameters['route-instance-id']!,
        url: state.uri.queryParameters['url']!,
        title: state.uri.queryParameters['title']!,
        articleId: _$convertMapValue(
          'article-id',
          state.uri.queryParameters,
          int.tryParse,
        ),
      );

  CollectionsReaderRouteData get _self => this as CollectionsReaderRouteData;

  @override
  String get location => GoRouteData.$location(
    '/profile/collections/read',
    queryParams: {
      'route-instance-id': _self.routeInstanceId,
      'url': _self.url,
      'title': _self.title,
      if (_self.articleId != null) 'article-id': _self.articleId!.toString(),
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

mixin $ThemeSettingsRouteData on GoRouteData {
  static ThemeSettingsRouteData _fromState(GoRouterState state) =>
      ThemeSettingsRouteData(
        routeInstanceId: state.uri.queryParameters['route-instance-id']!,
      );

  ThemeSettingsRouteData get _self => this as ThemeSettingsRouteData;

  @override
  String get location => GoRouteData.$location(
    '/profile/theme',
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

T? _$convertMapValue<T>(
  String key,
  Map<String, String> map,
  T? Function(String) converter,
) {
  final value = map[key];
  return value == null ? null : converter(value);
}
