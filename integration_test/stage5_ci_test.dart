import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wanandroid_flutter/src/app/app.dart';
import 'package:wanandroid_flutter/src/app/bootstrap/app_dependencies.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/search_suggestions_repository.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';
import 'package:wanandroid_flutter/src/model/search_history.dart';

import '../test/support/fixed_topic_repository.dart';

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  final Duration step = const Duration(milliseconds: 200);
  for (int waited = 0; waited < 10000; waited += step.inMilliseconds) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Expected widget did not appear: $finder');
}

Future<void> _settle(WidgetTester tester) async {
  // Fixed-duration pumps: the home carousel animates periodically, so
  // pumpAndSettle can wait forever. Explicit pumps keep the entry deterministic.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('stage 5 UI-07: theme, guest gates and controlled login', (
    tester,
  ) async {
    final _ControlledAuthRepository auth = _ControlledAuthRepository();
    final AppDependencies dependencies = buildAppDependencies();
    final ThemeController theme = dependencies.themeController;
    await theme.load();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeControllerProvider.overrideWithValue(theme),
          authRepositoryProvider.overrideWithValue(auth),
          collectionRepositoryProvider.overrideWithValue(
            dependencies.collectionRepository,
          ),
          articleRepositoryProvider.overrideWithValue(
            _EmptyArticleRepository(),
          ),
          topicRepositoryProvider.overrideWithValue(
            const FixedTopicRepository(),
          ),
          searchSuggestionsRepositoryProvider.overrideWithValue(
            _EmptySearchRepository(),
          ),
        ],
        child: const WanAndroidApp(),
      ),
    );
    await _settle(tester);

    // Profile tab shows the guest state and entries.
    await tester.tap(find.text('我的'));
    await _waitFor(tester, find.text('未登录'));
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('外观与主题'), findsOneWidget);

    // Theme settings apply a palette immediately.
    await tester.tap(find.text('外观与主题'));
    await _settle(tester);
    expect(find.text('配色风格'), findsOneWidget);
    await tester.tap(find.text('莓果玫瑰'));
    await _settle(tester);
    expect(theme.palette, WanPalette.berryRose);

    // The collections screen gates on login while the session is guest.
    await tester.tap(find.byTooltip('返回').last);
    await _settle(tester);
    await tester.tap(find.text('我的收藏'));
    await _settle(tester);
    expect(find.text('请登录后查看收藏'), findsOneWidget);

    // UI-07: a fixed Fake login traverses route -> ViewModel -> Repository.
    await tester.tap(find.byTooltip('返回').last);
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await _waitFor(tester, find.textContaining('欢迎登录 WanAndroid'));
    await tester.enterText(
      find.widgetWithText(TextField, '请输入手机号'),
      '13800138000',
    );
    await tester.enterText(find.widgetWithText(TextField, '请输入密码'), 'secret');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, '登录'));
    await tester.tap(find.widgetWithText(ElevatedButton, '登录'));
    await tester.pump();
    expect(find.text('正在登录…'), findsOneWidget);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(auth.loginCalls, 1);

    auth.completeLogin();
    await _waitFor(tester, find.text('fixture-user'));
    expect(find.text('fixture-user'), findsOneWidget);
  });

  testWidgets('stage 5 UI-07: leaving login cancels the in-flight request', (
    tester,
  ) async {
    final _ControlledAuthRepository auth = _ControlledAuthRepository();
    final AppDependencies dependencies = buildAppDependencies();
    final ThemeController theme = dependencies.themeController;
    await theme.load();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeControllerProvider.overrideWithValue(theme),
          authRepositoryProvider.overrideWithValue(auth),
          collectionRepositoryProvider.overrideWithValue(
            dependencies.collectionRepository,
          ),
          articleRepositoryProvider.overrideWithValue(
            _EmptyArticleRepository(),
          ),
          topicRepositoryProvider.overrideWithValue(
            const FixedTopicRepository(),
          ),
          searchSuggestionsRepositoryProvider.overrideWithValue(
            _EmptySearchRepository(),
          ),
        ],
        child: const WanAndroidApp(),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('我的'));
    await _waitFor(tester, find.text('未登录'));
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await _waitFor(tester, find.textContaining('欢迎登录 WanAndroid'));
    await tester.enterText(
      find.widgetWithText(TextField, '请输入手机号'),
      '13800138000',
    );
    await tester.enterText(find.widgetWithText(TextField, '请输入密码'), 'secret');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, '登录'));
    await tester.tap(find.widgetWithText(ElevatedButton, '登录'));
    await tester.pump();
    expect(auth.loginCalls, 1);

    await tester.binding.handlePopRoute();
    await _waitFor(tester, find.text('未登录'));
    expect(auth.cancellation?.isCancelled, isTrue);
    auth.completeLogin();
    await _settle(tester);
    expect(find.text('未登录'), findsOneWidget);
  });
}

class _ControlledAuthRepository extends ChangeNotifier
    implements AuthRepository {
  final Completer<DataResult<void>> _login = Completer<DataResult<void>>();
  int loginCalls = 0;
  RequestCancellation? cancellation;
  bool authenticated = false;

  void completeLogin() {
    if (_login.isCompleted) return;
    if (cancellation?.isCancelled != true) {
      authenticated = true;
      notifyListeners();
    }
    _login.complete(const DataSuccess<void>(null));
  }

  @override
  AuthStateView view() => AuthStateView(
    loading: false,
    authenticated: authenticated,
    unverified: false,
    expiredNotice: false,
    storageNotice: false,
    displayName: authenticated ? 'fixture-user' : null,
  );

  @override
  Future<DataResult<void>> login(
    String username,
    String password, {
    RequestCancellation cancellation = const LiveRequestCancellation(),
  }) {
    loginCalls += 1;
    this.cancellation = cancellation;
    return Future.any<DataResult<void>>(<Future<DataResult<void>>>[
      _login.future,
      cancellation.whenCancelled.then<DataResult<void>>(
        (_) => throw const RequestCancelledException(),
      ),
    ]);
  }

  @override
  Future<DataResult<void>> restore() async => const DataSuccess<void>(null);

  @override
  Future<LogoutOutcome> logout() async =>
      LogoutOutcome(generation: 1, remote: const DataSuccess<void>(null));
}

class _EmptyArticleRepository implements ArticleRepository {
  @override
  Future<DataResult<PageResult<Article>>> articles(
    int page,
    RequestCancellation cancellation,
  ) async => DataSuccess<PageResult<Article>>(
    PageResult<Article>(items: <Article>[], nextPage: null),
  );

  @override
  Future<DataResult<PageResult<Article>>> questionPage(
    int page,
    RequestCancellation cancellation,
  ) async => DataSuccess<PageResult<Article>>(
    PageResult<Article>(items: <Article>[], nextPage: null),
  );

  @override
  Future<DataResult<List<Article>>> questions(
    RequestCancellation cancellation,
  ) async => DataSuccess<List<Article>>(<Article>[]);

  @override
  Future<DataResult<PageResult<Article>>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) async => DataSuccess<PageResult<Article>>(
    PageResult<Article>(items: <Article>[], nextPage: null),
  );
}

class _EmptySearchRepository implements SearchSuggestionsRepository {
  @override
  Future<SearchHistory> loadHistory() async => const SearchHistory();

  @override
  Future<DataResult<List<String>>> hotKeys(
    RequestCancellation cancellation,
  ) async => DataSuccess<List<String>>(<String>[]);

  @override
  Future<bool> record(String keyword) async => true;

  @override
  Future<bool> clearHistory() async => true;
}
