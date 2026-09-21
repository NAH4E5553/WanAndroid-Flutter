import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wanandroid_flutter/src/app/app.dart';
import 'package:wanandroid_flutter/src/app/router/app_shell.dart';
import 'package:wanandroid_flutter/src/app/router/branch_restoration_controller.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/reader/reading_history_provider.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/database/reading_history_database.dart';
import 'package:wanandroid_flutter/src/data/network/service/wan_api_service.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_reading_history_repository.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/features/profile/view/reading_history_screen.dart';
import 'package:wanandroid_flutter/src/features/reader/view/article_reader_screen.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../test/support/fake_session_repositories.dart';
import '../test/support/fixed_topic_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerReaderHistoryTests();
}

void registerReaderHistoryTests() {
  testWidgets(
    'controlled WebView load writes local history; refresh retains instance',
    (tester) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '<!doctype html><title>Reader fixture</title><h1>Ready</h1>',
        );
        await request.response.close();
      });
      addTearDown(() async {
        await requests.cancel();
        await server.close(force: true);
      });
      final database = ReadingHistoryDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final history = DefaultReadingHistoryRepository(
        database,
        allowLoopbackFixture: true,
      );
      final url = 'http://localhost:${server.port}/first';
      var exits = 0;
      WebViewController? controller;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            readingHistoryRepositoryProvider.overrideWithValue(history),
          ],
          child: MaterialApp(
            home: ArticleReaderScreen(
              articleId: 41,
              title: 'Reader fixture',
              url: url,
              allowLoopbackFixture: true,
              onExit: () => exits++,
              onPopped: () {},
              onControllerReady: (ready) => controller = ready,
            ),
          ),
        ),
      );
      await _waitFor(tester, () async => (await history.page()).length == 1);
      expect((await history.page()).single.articleId, 41);
      final WebViewWidget webView = tester.widget(find.byType(WebViewWidget));
      expect(webView.key, const ValueKey<int>(1));
      await controller!.loadRequest(Uri.parse(url).resolve('/second'));
      await _waitFor(tester, () async => (await history.page()).length == 2);
      expect(
        (await history.page())
            .singleWhere((row) => row.url.endsWith('/second'))
            .articleId,
        isNull,
      );
      await _waitFor(tester, controller!.canGoBack);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('返回').last);
      await _waitFor(
        tester,
        () async =>
            (await controller!.currentUrl())?.endsWith('/first') ?? false,
      );
      expect(exits, 0);
      if (defaultTargetPlatform == TargetPlatform.android) {
        await controller!.loadRequest(Uri.parse(url).resolve('/second'));
        await _waitFor(
          tester,
          () async =>
              (await controller!.currentUrl())?.endsWith('/second') ?? false,
        );
        await _waitFor(tester, controller!.canGoBack);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.binding.handlePopRoute();
        await _waitFor(
          tester,
          () async =>
              (await controller!.currentUrl())?.endsWith('/first') ?? false,
        );
        expect(exits, 0);
      }
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('刷新'));
      await tester.pump(const Duration(milliseconds: 300));
      final WebViewWidget refreshed = tester.widget(find.byType(WebViewWidget));
      expect(refreshed.key, const ValueKey<int>(1));
    },
  );

  testWidgets('timeout retry replaces instance and ignores late old load', (
    tester,
  ) async {
    var count = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) async {
      count++;
      if (count == 1) await Future<void>.delayed(const Duration(seconds: 6));
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<!doctype html><title>Same URL</title><h1>Ready</h1>',
      );
      await request.response.close();
    });
    addTearDown(() async {
      await requests.cancel();
      await server.close(force: true);
    });
    final database = ReadingHistoryDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final history = DefaultReadingHistoryRepository(
      database,
      allowLoopbackFixture: true,
    );
    Widget readerWithTimeout(Duration timeout) => ProviderScope(
      overrides: [readingHistoryRepositoryProvider.overrideWithValue(history)],
      child: MaterialApp(
        home: ArticleReaderScreen(
          key: const ValueKey<String>('same-url-reader'),
          articleId: 42,
          title: 'Same URL',
          url: 'http://localhost:${server.port}/same',
          allowLoopbackFixture: true,
          loadTimeout: timeout,
          onExit: () {},
          onPopped: () {},
        ),
      ),
    );
    await tester.pumpWidget(readerWithTimeout(const Duration(seconds: 2)));
    await _waitFor(tester, () async => count >= 1);
    await _waitFor(tester, () async => find.text('加载超时').evaluate().isNotEmpty);
    await tester.pumpWidget(readerWithTimeout(const Duration(seconds: 12)));
    await tester.tap(find.text('重试'));
    await _waitFor(tester, () async => (await history.page()).length == 1);
    expect(
      tester.widget<WebViewWidget>(find.byType(WebViewWidget)).key,
      const ValueKey<int>(2),
    );
    await tester.pump(const Duration(seconds: 7));
    expect((await history.page()).length, 1);
    expect(find.text('加载超时'), findsNothing);
  });

  testWidgets('disposed reader cannot record a delayed page after reentry', (
    tester,
  ) async {
    final firstResponse = Completer<void>();
    final firstFinished = Completer<void>();
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) async {
      final isFirst = ++requestCount == 1;
      if (isFirst) await firstResponse.future;
      try {
        request.response.headers.contentType = ContentType.html;
        request.response.write('<!doctype html><h1>Reader lifecycle</h1>');
        await request.response.close();
      } on SocketException {
        // Disposing the first platform view may close its pending connection.
      } finally {
        if (isFirst) firstFinished.complete();
      }
    });
    addTearDown(() async {
      if (!firstResponse.isCompleted) firstResponse.complete();
      await requests.cancel();
      await server.close(force: true);
    });
    final database = ReadingHistoryDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final history = DefaultReadingHistoryRepository(
      database,
      allowLoopbackFixture: true,
    );
    final url = 'http://localhost:${server.port}/lifecycle';
    Widget reader(int articleId, String title) => ProviderScope(
      overrides: [readingHistoryRepositoryProvider.overrideWithValue(history)],
      child: MaterialApp(
        home: ArticleReaderScreen(
          articleId: articleId,
          title: title,
          url: url,
          allowLoopbackFixture: true,
          onExit: () {},
          onPopped: () {},
        ),
      ),
    );

    await tester.pumpWidget(reader(71, 'Old reader'));
    await _waitFor(tester, () => requestCount == 1);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Reader exited'))),
    );
    expect(await history.page(), isEmpty);

    await tester.pumpWidget(reader(72, 'New reader'));
    await _waitFor(tester, () async => (await history.page()).length == 1);
    expect((await history.page()).single.articleId, 72);
    firstResponse.complete();
    await firstFinished.future.timeout(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    final rows = await history.page();
    expect(rows, hasLength(1));
    expect(rows.single.articleId, 72);
    expect(rows.single.title, 'New reader');
  });

  testWidgets(
    'profile history route opens and returns without losing its list',
    (tester) async {
      final database = ReadingHistoryDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final history = DefaultReadingHistoryRepository(database);
      await history.record(
        url: 'https://localhost/history',
        title: '历史入口文章',
        articleId: 51,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            readingHistoryRepositoryProvider.overrideWithValue(history),
            articleRepositoryProvider.overrideWithValue(const _EmptyArticles()),
            topicRepositoryProvider.overrideWithValue(
              const FixedTopicRepository(),
            ),
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            collectionRepositoryProvider.overrideWithValue(
              FakeCollectionRepository(),
            ),
          ],
          child: const WanAndroidApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.text('阅读历史'));
      final branch = BranchRestorationScope.of(
        tester.element(find.byType(AppShell)),
      );
      await _waitFor(tester, () => branch.snapshot.stacks[2].length == 2);
      expect(find.text('历史入口文章'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.text('历史入口文章'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(branch.snapshot.stacks[2].length, 3);
      expect(find.byType(ArticleReaderScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ArticleReaderScreen),
          matching: find.byIcon(Icons.more_vert),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(ArticleReaderScreen),
          matching: find.byTooltip('返回'),
        ),
      );
      await _waitFor(tester, () => branch.snapshot.stacks[2].length == 2);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(ReadingHistoryScreen),
          matching: find.byTooltip('返回'),
        ),
      );
      await _waitFor(tester, () => branch.snapshot.stacks[2].length == 1);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
    },
  );

  testWidgets('API requests do not inherit WebView cookies', (tester) async {
    String? apiCookie;
    String? readerCookie;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) async {
      if (request.uri.path == '/article/list/0/json') {
        apiCookie = request.headers.value('cookie');
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"errorCode":0,"data":[]}');
      } else {
        readerCookie = request.headers.value('cookie');
        request.response.headers.contentType = ContentType.html;
        request.response.write('<!doctype html><h1>Cookie fixture</h1>');
      }
      await request.response.close();
    });
    addTearDown(() async {
      await requests.cancel();
      await server.close(force: true);
    });
    final cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();
    addTearDown(cookieManager.clearCookies);
    await cookieManager.setCookie(
      const WebViewCookie(
        name: 'reader_fixture',
        value: 'visible',
        domain: 'localhost',
        path: '/',
      ),
    );
    final base = 'http://localhost:${server.port}/';
    final service = DioWanApiService(dio: Dio(BaseOptions(baseUrl: base)));
    await service.articles(0, DefaultRequestCancellationController().signal);
    expect(apiCookie, isNull);
    final database = ReadingHistoryDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final history = DefaultReadingHistoryRepository(
      database,
      allowLoopbackFixture: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readingHistoryRepositoryProvider.overrideWithValue(history),
        ],
        child: MaterialApp(
          home: ArticleReaderScreen(
            articleId: null,
            title: 'Cookie fixture',
            url: '${base}reader',
            allowLoopbackFixture: true,
            onExit: () {},
            onPopped: () {},
          ),
        ),
      ),
    );
    await _waitFor(tester, () => readerCookie != null);
    expect(readerCookie, contains('reader_fixture=visible'));
    expect(readerCookie, isNot(contains('api_session')));
  });

  testWidgets(
    'controlled HTTP main error and broken subresource stay distinct',
    (tester) async {
      var mainHits = 0;
      var childHits = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        switch (request.uri.path) {
          case '/main-500':
            mainHits++;
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write('<h1>Controlled 500</h1>');
          case '/child-error':
            childHits++;
            request.response.write(
              '<h1>Readable page</h1><img src="/missing.png">',
            );
          default:
            request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      addTearDown(() async {
        await requests.cancel();
        await server.close(force: true);
      });
      final database = ReadingHistoryDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final history = DefaultReadingHistoryRepository(
        database,
        allowLoopbackFixture: true,
      );
      Widget page(String path) => ProviderScope(
        overrides: [
          readingHistoryRepositoryProvider.overrideWithValue(history),
        ],
        child: MaterialApp(
          home: ArticleReaderScreen(
            key: ValueKey(path),
            articleId: 60,
            title: 'Error fixture',
            url: 'http://localhost:${server.port}/$path',
            allowLoopbackFixture: true,
            onExit: () {},
            onPopped: () {},
          ),
        ),
      );
      await tester.pumpWidget(page('main-500'));
      await _waitFor(tester, () => mainHits > 0);
      await tester.pump(const Duration(seconds: 1));
      expect(await history.page(), isEmpty);
      if (defaultTargetPlatform == TargetPlatform.android) {
        expect(find.text('页面响应异常'), findsOneWidget);
      }

      await tester.pumpWidget(page('child-error'));
      await _waitFor(tester, () => childHits > 0);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('页面响应异常'), findsNothing);
      expect(find.text('页面加载失败'), findsNothing);
      if (defaultTargetPlatform == TargetPlatform.android) {
        expect((await history.page()).single.url, endsWith('/child-error'));
      }
    },
  );
}

class _EmptyArticles implements ArticleRepository {
  const _EmptyArticles();

  @override
  Future<DataResult<PageResult<Article>>> articles(
    int page,
    RequestCancellation cancellation,
  ) async => const DataSuccess(PageResult(items: <Article>[], nextPage: null));

  @override
  Future<DataResult<PageResult<Article>>> questionPage(
    int page,
    RequestCancellation cancellation,
  ) async => const DataSuccess(PageResult(items: <Article>[], nextPage: null));

  @override
  Future<DataResult<List<Article>>> questions(
    RequestCancellation cancellation,
  ) async => const DataSuccess(<Article>[]);

  @override
  Future<DataResult<PageResult<Article>>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) async => const DataSuccess(PageResult(items: <Article>[], nextPage: null));
}

Future<void> _waitFor(
  WidgetTester tester,
  FutureOr<bool> Function() condition,
) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (await condition()) return;
  }
  fail('Controlled WebView condition did not occur within 12 seconds');
}
