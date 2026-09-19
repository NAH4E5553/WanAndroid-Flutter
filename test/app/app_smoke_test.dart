import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/app/app.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/search_suggestions_repository.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';
import 'package:wanandroid_flutter/src/model/search_history.dart';

import '../support/fixed_topic_repository.dart';

void main() {
  testWidgets('renders the home vertical slice from repository contracts', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          articleRepositoryProvider.overrideWithValue(_AppArticleRepository()),
          topicRepositoryProvider.overrideWithValue(
            const FixedTopicRepository(),
          ),
          searchSuggestionsRepositoryProvider.overrideWithValue(
            _AppSearchSuggestionsRepository(),
          ),
        ],
        child: const WanAndroidApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('每日一问'), findsOneWidget);
    expect(find.text('最新博文'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('专题'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}

class _AppArticleRepository implements ArticleRepository {
  @override
  Future<DataResult<PageResult<Article>>> articles(
    int page,
    RequestCancellation cancellation,
  ) async => DataSuccess<PageResult<Article>>(
    PageResult<Article>(items: const <Article>[_article], nextPage: null),
  );

  @override
  Future<DataResult<List<Article>>> questions(
    RequestCancellation cancellation,
  ) async => const DataSuccess<List<Article>>(<Article>[_question]);

  @override
  Future<DataResult<PageResult<Article>>> questionPage(
    int page,
    RequestCancellation cancellation,
  ) async => DataSuccess<PageResult<Article>>(
    PageResult<Article>(items: const <Article>[_question], nextPage: null),
  );

  @override
  Future<DataResult<PageResult<Article>>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) async => DataSuccess<PageResult<Article>>(
    const PageResult<Article>(items: <Article>[], nextPage: null),
  );
}

class _AppSearchSuggestionsRepository implements SearchSuggestionsRepository {
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

const Article _article = Article(
  id: 101,
  title: '用固定数据建立首页垂直切片',
  url: 'https://fixture.invalid/a',
  author: '作者',
  shareUser: '',
  superChapterName: '开发实践',
  chapter: 'Flutter',
  publishedAt: '2026-09-18',
  collected: false,
);

const Article _question = Article(
  id: 201,
  title: 'Flutter 中如何保持页面状态？',
  url: 'https://fixture.invalid/q',
  author: '作者',
  shareUser: '',
  superChapterName: '每日一问',
  chapter: 'Flutter',
  publishedAt: '2026-09-18',
  collected: false,
);
