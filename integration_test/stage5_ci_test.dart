import 'dart:async';

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
import 'package:wanandroid_flutter/src/data/repository/contract/search_suggestions_repository.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';
import 'package:wanandroid_flutter/src/model/search_history.dart';

import '../test/support/fixed_topic_repository.dart';

Future<void> _settle(WidgetTester tester) async {
  // Fixed-duration pumps: the home carousel animates periodically, so
  // pumpAndSettle can wait forever. Explicit pumps keep the entry deterministic.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('stage 5: theme, profile guest state and login gates', (
    tester,
  ) async {
    final AppDependencies dependencies = buildAppDependencies();
    final ThemeController theme = dependencies.themeController;
    await theme.load();
    unawaited(dependencies.authRepository.restore());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeControllerProvider.overrideWithValue(theme),
          sessionStoreProvider.overrideWithValue(dependencies.sessionStore),
          authRepositoryProvider.overrideWithValue(dependencies.authRepository),
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
    await _settle(tester);
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('外观与主题'), findsOneWidget);

    // Theme settings apply a palette immediately.
    await tester.tap(find.text('外观与主题'));
    await _settle(tester);
    expect(find.text('配色风格'), findsOneWidget);
    await tester.tap(find.text('莓果玫瑰'));
    await _settle(tester);
    // ignore: avoid_print
    print(
      'STAGE5_DEBUG palette=${theme.palette} saveFailed=${theme.saveFailed} saving=${theme.saving}',
    );
    expect(theme.palette, WanPalette.berryRose);

    // The collections screen gates on login while the session is guest.
    await tester.tap(find.byTooltip('返回').last);
    await _settle(tester);
    await tester.tap(find.text('我的收藏'));
    await _settle(tester);
    expect(find.text('请登录后查看收藏'), findsOneWidget);
  });
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
