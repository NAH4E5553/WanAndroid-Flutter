import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wanandroid_flutter/src/app/app.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerNavigationRestorationTests();
}

void registerNavigationRestorationTests() {
  testWidgets('restores the inactive home detail stack and active branch', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          articleRepositoryProvider.overrideWithValue(
            _NavigationArticleRepository(),
          ),
        ],
        child: const WanAndroidApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('用固定 Fake 数据建立第一个 Flutter 垂直切片'));
    await tester.pumpAndSettle();
    expect(find.text('文章预览 #101'), findsOneWidget);

    await tester.tap(find.text('专题'));
    await tester.pumpAndSettle();
    expect(find.text('专题完整交互将在阶段 3 实现。'), findsOneWidget);

    await tester.restartAndRestore();
    await tester.pumpAndSettle();
    expect(
      find.text('专题完整交互将在阶段 3 实现。'),
      findsOneWidget,
      reason: 'Visible texts after restore: ${_visibleTexts(tester)}',
    );

    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(find.text('文章预览 #101'), findsOneWidget);
  });
}

class _NavigationArticleRepository implements ArticleRepository {
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

const Article _article = Article(
  id: 101,
  title: '用固定 Fake 数据建立第一个 Flutter 垂直切片',
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

List<String> _visibleTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text widget) => widget.data)
    .whereType<String>()
    .toList(growable: false);
