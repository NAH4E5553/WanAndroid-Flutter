import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Minimal stage-0 shell used to inspect branch and route restoration.
class NavigationPrototypeApp extends StatefulWidget {
  const NavigationPrototypeApp({super.key});

  @override
  State<NavigationPrototypeApp> createState() => _NavigationPrototypeAppState();
}

class _NavigationPrototypeAppState extends State<NavigationPrototypeApp> {
  late final GoRouter _router;
  final _routeIds = _RouteInstanceIdGenerator();

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/home',
      restorationScopeId: 'navigation-router',
      routes: [
        StatefulShellRoute.indexedStack(
          restorationScopeId: 'navigation-shell',
          pageBuilder: (context, state, navigationShell) => MaterialPage<void>(
            restorationId: 'navigation-shell-page',
            child: _PrototypeShell(navigationShell: navigationShell),
          ),
          branches: [
            StatefulShellBranch(
              restorationScopeId: 'home-branch',
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (context, state) =>
                      _HomePage(openArticle: () => _pushArticle(context, '42')),
                  routes: [
                    GoRoute(
                      path: 'detail/:articleId',
                      builder: (context, state) {
                        final articleId = state.pathParameters['articleId']!;
                        final routeInstanceId =
                            state.uri.queryParameters['routeInstanceId'] ??
                            'missing';
                        return _DetailPage(
                          articleId: articleId,
                          routeInstanceId: routeInstanceId,
                          pushSameArticle: () =>
                              _pushArticle(context, articleId),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              restorationScopeId: 'topics-branch',
              routes: [
                GoRoute(
                  path: '/topics',
                  builder: (context, state) => const _TopicsPage(),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  void _pushArticle(BuildContext context, String articleId) {
    final id = _routeIds.next();
    context.push('/home/detail/$articleId?routeInstanceId=$id');
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    restorationScopeId: 'navigation-prototype',
    routerConfig: _router,
  );
}

final class _RouteInstanceIdGenerator {
  static int _lastTimestamp = 0;

  String next() {
    final now = DateTime.now().microsecondsSinceEpoch;
    _lastTimestamp = now > _lastTimestamp ? now : _lastTimestamp + 1;
    return _lastTimestamp.toString();
  }
}

class _PrototypeShell extends StatelessWidget {
  const _PrototypeShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        'branch:${navigationShell.currentIndex}',
        key: const ValueKey('branch-index'),
      ),
    ),
    body: navigationShell,
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: navigationShell.currentIndex,
      onTap: (index) => navigationShell.goBranch(index),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.category), label: 'Topics'),
      ],
    ),
  );
}

class _HomePage extends StatelessWidget {
  const _HomePage({required this.openArticle});

  final VoidCallback openArticle;

  @override
  Widget build(BuildContext context) => Center(
    child: FilledButton(
      key: const ValueKey('push-detail'),
      onPressed: openArticle,
      child: const Text('Open article 42'),
    ),
  );
}

class _TopicsPage extends StatelessWidget {
  const _TopicsPage();

  @override
  Widget build(BuildContext context) => const Center(
    child: Text('Topics branch', key: ValueKey('topics-screen')),
  );
}

class _DetailPage extends StatelessWidget {
  const _DetailPage({
    required this.articleId,
    required this.routeInstanceId,
    required this.pushSameArticle,
  });

  final String articleId;
  final String routeInstanceId;
  final VoidCallback pushSameArticle;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('article:$articleId', key: const ValueKey('article-id')),
        Text(routeInstanceId, key: const ValueKey('route-instance-id')),
        FilledButton(
          key: const ValueKey('push-same-detail'),
          onPressed: pushSameArticle,
          child: const Text('Push article 42 again'),
        ),
        FilledButton(
          key: const ValueKey('pop-detail'),
          onPressed: () => context.pop(),
          child: const Text('Back'),
        ),
      ],
    ),
  );
}
