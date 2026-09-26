import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_storage.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/core/ui/article_card.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/collection_repository.dart';
import 'package:wanandroid_flutter/src/features/profile/view/collections_screen.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/collection.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

class _SignedInCollectionRepository extends ChangeNotifier
    implements CollectionRepository {
  _SignedInCollectionRepository() {
    _snapshot = const CollectionSnapshot(generation: 1, sessionKey: 'test:1');
  }

  CollectionSnapshot _snapshot = const CollectionSnapshot();

  @override
  CollectionSnapshot get current => _snapshot;

  @override
  Future<DataResult<PageResult<Article>>> articlePage(
    Future<DataResult<PageResult<Article>>> Function() load,
  ) => load();

  @override
  Future<DataResult<PageResult<CollectionItem>>> page(
    int generation,
    int page,
  ) async {
    final CollectionItem item = CollectionItem(
      target: const CollectionTarget(42, 501),
      article: Article(
        id: 42,
        title: '被收藏的文章标题',
        url: 'https://wanandroid.com/a/42',
        author: '作者',
        shareUser: '',
        superChapterName: '软件',
        chapter: '开发',
        publishedAt: '2026-09-21',
        collected: true,
      ),
    );
    return DataSuccess<PageResult<CollectionItem>>(
      PageResult<CollectionItem>(items: <CollectionItem>[item], nextPage: null),
    );
  }

  @override
  Future<DataResult<void>> reconcile(
    int generation,
    CollectionTarget target,
  ) async => const DataSuccess<void>(null);

  @override
  Future<DataResult<void>> setCollected(
    int generation,
    CollectionTarget target,
    bool collected,
  ) async {
    _snapshot = _snapshot.copyWith(revision: _snapshot.revision + 1);
    notifyListeners();
    return const DataSuccess<void>(null);
  }
}

class _MemoryThemePreferences implements ThemeStorage {
  @override
  Future<({WanPalette palette, ThemeMode mode})?> read() async => null;

  @override
  Future<void> write(WanPalette palette, ThemeMode mode) async {}
}

void main() {
  for (final Brightness brightness in <Brightness>[
    Brightness.light,
    Brightness.dark,
  ]) {
    testWidgets(
      'collection rows use home-style cards with category and time ($brightness)',
      (WidgetTester tester) async {
        int articleTaps = 0;
        final ThemeController theme = ThemeController(
          preferences: _MemoryThemePreferences(),
        );
        await theme.load();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              themeControllerProvider.overrideWithValue(theme),
              collectionRepositoryProvider.overrideWithValue(
                _SignedInCollectionRepository(),
              ),
            ],
            child: MaterialApp(
              theme: wanTheme(brightness: brightness),
              home: CollectionsScreen(
                onBack: () {},
                onLoginTap: () {},
                onArticleTap: (String url, String title, int? articleId) {
                  articleTaps += 1;
                },
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Home-style card with category and time lines.
        expect(find.byType(ArticleCard), findsOneWidget);
        expect(find.textContaining('分类：'), findsOneWidget);
        expect(find.text('时间：2026-09-21'), findsOneWidget);
        expect(find.byTooltip('取消收藏'), findsNothing);
        expect(
          tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
          Offset.zero,
        );
        final Rect closedRowRect = tester.getRect(
          find
              .ancestor(
                of: find.text('被收藏的文章标题'),
                matching: find.byType(ClipRRect),
              )
              .first,
        );
        final Rect closedCardRect = tester.getRect(find.byType(ArticleCard));
        expect(closedCardRect.left, closeTo(closedRowRect.left, 0.01));
        expect(closedCardRect.right, closeTo(closedRowRect.right, 0.01));

        await tester.drag(find.byType(ArticleCard), const Offset(-100, 0));
        await tester.pumpAndSettle();
        expect(find.byTooltip('取消收藏'), findsOneWidget);
        expect(
          tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset.dx,
          lessThan(0),
        );

        // Tapping an already revealed row closes the action instead of
        // navigating away and preserving the destructive state underneath.
        await tester.tap(find.text('被收藏的文章标题'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('取消收藏'), findsNothing);
        expect(
          tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
          Offset.zero,
        );
        expect(articleTaps, 0);

        await tester.tap(find.text('被收藏的文章标题'));
        await tester.pump();
        expect(articleTaps, 1);

        await tester.drag(find.byType(ArticleCard), const Offset(-100, 0));
        await tester.pumpAndSettle();
        expect(find.byTooltip('取消收藏'), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('取消收藏'), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );

        // The card surface paints the same role the history rows use.
        final BuildContext context = tester.element(find.text('被收藏的文章标题'));
        final Color expected = Theme.of(context)
            .colorScheme
            .surfaceContainerLow;
        final Material cardMaterial = tester.widget<Material>(
          find
              .ancestor(
                of: find.text('被收藏的文章标题'),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(cardMaterial.color, expected);
      },
    );
  }
}
