import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/app/app.dart';
import 'package:wanandroid_flutter/src/app/startup/startup_reveal_layer.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/diagnostics/startup_metrics.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_state.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/startup/startup_reveal_controller.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/features/home/state/home_ui_state.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_view_model.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

import '../../support/fake_avatar_dependencies.dart';
import '../../support/fake_session_repositories.dart';
import '../../support/fixed_topic_repository.dart';

// Second independent review: verify visible behavior through the actual layer
// and production composition, rather than directly calling a new fast-path API.
void main() {
  testWidgets('startup handoff restores target page accessibility', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: StartupRevealLayer(child: Text('accessible target')),
          ),
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('accessible target'), findsNothing);
      await tester.pump(const Duration(milliseconds: 480));
      await tester.pump(const Duration(milliseconds: 220));
      expect(
        find.byKey(const ValueKey<String>('startup-overlay')),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel('accessible target'),
        findsOneWidget,
        reason: 'After launch, the target page must be available to screen readers.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('first Flutter icon frame matches the native unscaled image', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: StartupRevealLayer(child: Text('target'))),
      ),
    );
    final ScaleTransition scale = tester.widget<ScaleTransition>(
      find.descendant(
        of: find.byType(AnimatedScale),
        matching: find.byType(ScaleTransition),
      ),
    );
    expect(
      scale.scale.value,
      closeTo(1, .0001),
      reason: 'The first painted glyph must match the native 96dp/76pt size.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('production ready home exits before the full teaser', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _readyAppContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const WanAndroidApp(),
      ),
    );
    await tester.pump();
    // Both lists already contain successful data. No manual markContentReady call:
    // production wiring must deliver this fact to the presentation controller.
    expect(
      container.read(homeViewModelProvider).articles.isInitialLoading,
      false,
    );
    expect(container.read(homeViewModelProvider).articles.items, hasLength(1));
    expect(container.read(homeViewModelProvider).questions.items, hasLength(1));
    await tester.pump(const Duration(milliseconds: 320));
    expect(
      container.read(startupRevealControllerProvider).isDone,
      isTrue,
      reason: 'A ready home must not wait for the full 480ms + 220ms teaser.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final bool productionHome in <bool>[false, true]) {
    testWidgets(
      'production records exit and visible home across real frame windows (production HomeViewModel=$productionHome)',
      (WidgetTester tester) async {
        final StartupMetrics previous = StartupMetrics.instance;
        final List<Map<String, Object>> events = <Map<String, Object>>[];
        int frameBuild = 100;
        final StartupMetrics metrics = StartupMetrics(
          enabled: true,
          // FrameTiming's build window ends before post-frame callbacks. Giving
          // these distinct times prevents an outside-build report from passing
          // merely because the fake clock is constant for the whole pump.
          clock: () =>
              frameBuild +
              (SchedulerBinding.instance.schedulerPhase ==
                      SchedulerPhase.postFrameCallbacks
                  ? 100
                  : 0),
          emit: events.add,
        )..start();
        StartupMetrics.instance = metrics;
        addTearDown(() {
          metrics.detach();
          StartupMetrics.instance = previous;
        });
        final ProviderContainer container = _readyAppContainer(
          productionHome: productionHome,
        );
        addTearDown(container.dispose);
        final List<FrameTiming> frames = <FrameTiming>[];
        int? firstUncoveredBuild;
        void captureFrame() {
          frames.add(_frame(frameBuild));
          if (find
              .byKey(const ValueKey<String>('startup-overlay'))
              .evaluate()
              .isEmpty) {
            firstUncoveredBuild ??= frameBuild;
          }
        }

        Future<void> pumpFrame([Duration elapsed = Duration.zero]) async {
          frameBuild += 200;
          tester.binding.scheduleFrame();
          await tester.pump(elapsed);
          captureFrame();
        }

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const WanAndroidApp(),
          ),
        );
        captureFrame();
        await pumpFrame();
        await pumpFrame(const Duration(milliseconds: 480));
        await pumpFrame(const Duration(milliseconds: 220));
        expect(container.read(startupRevealControllerProvider).isDone, isTrue);
        await pumpFrame();
        expect(
          find.byKey(const ValueKey<String>('startup-overlay')),
          findsNothing,
        );
        frameBuild += 200; // Timing delivery occurs after raster completion.
        metrics.recordTimings(frames);
        expect(
          events.where((e) => e['point'] == 'startup_layer_exit'),
          hasLength(1),
          reason: 'The removal frame must emit its exit marker; events=$events',
        );
        expect(
          events.where((e) => e['point'] == 'home_terminal_raster'),
          hasLength(1),
          reason:
              'A ready page is visible in this raster; a post-frame invocation '
              'is outside its build window and cannot measure that frame.',
        );
        int timeOf(String point) =>
            events.singleWhere((e) => e['point'] == point)['dart_us']! as int;
        expect(timeOf('startup_layer_exit'), firstUncoveredBuild! + 60 - 100);
        expect(
          timeOf('home_first_raster'),
          greaterThanOrEqualTo(timeOf('startup_layer_exit')),
        );
        expect(
          events.where((e) => e['point'] == 'home_first_raster'),
          hasLength(1),
        );
        expect(
          events.where((e) => e['point'] == 'home_articles_raster'),
          hasLength(1),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

ProviderContainer _readyAppContainer({bool productionHome = false}) =>
    ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        avatarRepositoryProvider.overrideWithValue(FakeAvatarRepository()),
        collectionRepositoryProvider.overrideWithValue(
          FakeCollectionRepository(),
        ),
        topicRepositoryProvider.overrideWithValue(const FixedTopicRepository()),
        if (productionHome)
          articleRepositoryProvider.overrideWithValue(_ReadyArticleRepository())
        else
          homeViewModelProvider.overrideWith(_ReadyHomeViewModel.new),
      ],
    );

class _ReadyArticleRepository implements ArticleRepository {
  @override
  Future<DataResult<PageResult<Article>>> articles(
    int page,
    RequestCancellation cancellation,
  ) async => const DataSuccess<PageResult<Article>>(
    PageResult<Article>(items: <Article>[_readyArticle], nextPage: null),
  );
  @override
  Future<DataResult<List<Article>>> questions(
    RequestCancellation cancellation,
  ) async => const DataSuccess<List<Article>>(<Article>[_readyArticle]);
  @override
  Future<DataResult<PageResult<Article>>> questionPage(
    int page,
    RequestCancellation cancellation,
  ) => throw UnimplementedError();
  @override
  Future<DataResult<PageResult<Article>>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) => throw UnimplementedError();
}

class _ReadyHomeViewModel extends HomeViewModel {
  @override
  HomeUiState build() => const HomeUiState().copyWith(
    articles: const HomeUiState().articles.copyWith(
      initial: const LoadIdle(),
      items: const <Article>[_readyArticle],
    ),
    questions: const QuestionUiState(
      items: <Article>[_readyArticle],
      loading: false,
    ),
  );
}

const Article _readyArticle = Article(
  id: 101,
  title: 'ready fixture article',
  url: 'https://fixture.invalid/ready',
  author: 'fixture author',
  shareUser: '',
  superChapterName: 'fixture chapter',
  chapter: 'fixture',
  publishedAt: '2026-10-01',
  collected: false,
);

FrameTiming _frame(int build) => FrameTiming(
  vsyncStart: build - 1,
  buildStart: build,
  buildFinish: build + 40,
  rasterStart: build + 41,
  rasterFinish: build + 60,
  rasterFinishWallTime: build + 60,
);
