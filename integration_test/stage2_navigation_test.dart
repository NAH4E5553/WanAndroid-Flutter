import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wanandroid_flutter/src/app/app.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/search_suggestions_repository.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';
import 'package:wanandroid_flutter/src/model/search_history.dart';

import '../test/support/fake_session_repositories.dart';
import '../test/support/fixed_topic_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerStage2NavigationTests();
}

void registerStage2NavigationTests() {
  testWidgets('opens search results and the daily questions page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          collectionRepositoryProvider.overrideWithValue(
            FakeCollectionRepository(),
          ),
          articleRepositoryProvider.overrideWithValue(_Articles()),
          topicRepositoryProvider.overrideWithValue(
            const FixedTopicRepository(),
          ),
          searchSuggestionsRepositoryProvider.overrideWithValue(_Suggestions()),
        ],
        child: const WanAndroidApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.getSize(find.byType(PageView).first).height, 156);

    await tester.tap(find.text('搜索文章、技术与知识'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    await tester.enterText(find.byType(EditableText), 'Flutter');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.pumpAndSettle();
    expect(find.text('阶段 2 搜索结果'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('查看更多'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('阶段 2 每日一问'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}

class _Articles implements ArticleRepository {
  @override
  Future<DataResult<PageResult<Article>>> articles(
    int page,
    RequestCancellation cancellation,
  ) async => const DataSuccess<PageResult<Article>>(
    PageResult<Article>(items: <Article>[_home], nextPage: null),
  );

  @override
  Future<DataResult<PageResult<Article>>> questionPage(
    int page,
    RequestCancellation cancellation,
  ) async => const DataSuccess<PageResult<Article>>(
    PageResult<Article>(items: <Article>[_question], nextPage: null),
  );

  @override
  Future<DataResult<List<Article>>> questions(
    RequestCancellation cancellation,
  ) async => const DataSuccess<List<Article>>(<Article>[_question]);

  @override
  Future<DataResult<PageResult<Article>>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) async => const DataSuccess<PageResult<Article>>(
    PageResult<Article>(items: <Article>[_search], nextPage: null),
  );
}

class _Suggestions implements SearchSuggestionsRepository {
  @override
  Future<bool> clearHistory() async => true;

  @override
  Future<DataResult<List<String>>> hotKeys(
    RequestCancellation cancellation,
  ) async => const DataSuccess<List<String>>(<String>['Flutter']);

  @override
  Future<SearchHistory> loadHistory() async => const SearchHistory(ready: true);

  @override
  Future<bool> record(String keyword) async => true;
}

const Article _home = Article(
  id: 1,
  title: '阶段 2 首页文章',
  url: 'https://fixture.invalid/home',
  author: 'fixture',
  shareUser: '',
  superChapterName: '首页',
  chapter: 'Flutter',
  publishedAt: '2026-09-18',
  collected: false,
);

const Article _question = Article(
  id: 2,
  title: '阶段 2 每日一问',
  url: 'https://fixture.invalid/question',
  author: 'fixture',
  shareUser: '',
  superChapterName: '问答',
  chapter: 'Flutter',
  publishedAt: '2026-09-18',
  collected: false,
);

const Article _search = Article(
  id: 3,
  title: '阶段 2 搜索结果',
  url: 'https://fixture.invalid/search',
  author: 'fixture',
  shareUser: '',
  superChapterName: '搜索',
  chapter: 'Flutter',
  publishedAt: '2026-09-18',
  collected: false,
);
