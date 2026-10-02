import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/app/startup/startup_reveal_layer.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/diagnostics/startup_metrics.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/startup/startup_reveal_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/features/home/view/home_screen.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

/// STARTUP-02 回归：启动层遮挡期间，首页帧不得完成启动测点；
/// 启动层退出后的真实首页帧才完成（文章/问答请求在遮挡期间照常发出）。
void main() {
  testWidgets('occluded home frames do not complete startup points', (
    tester,
  ) async {
    final StartupMetrics previous = StartupMetrics.instance;
    int clock = 100;
    final List<Map<String, Object>> events = <Map<String, Object>>[];
    final StartupMetrics metrics = StartupMetrics(
      enabled: true,
      clock: () => clock,
      emit: events.add,
    )..start();
    StartupMetrics.instance = metrics;
    addTearDown(() => StartupMetrics.instance = previous);

    final _ControlledArticleRepository repository =
        _ControlledArticleRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: [articleRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: wanTheme(
            palette: WanPalette.slateBlue,
            brightness: Brightness.light,
          ),
          home: StartupRevealLayer(
            child: HomeScreen(
              onArticleTap: (_) {},
              onSearchTap: () {},
              onViewAllQuestions: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // 遮挡期间请求照常发出：动画不阻塞业务初始化。
    expect(repository.articleRequests, hasLength(1));
    expect(
      events.where((e) => e['point'].toString().startsWith('home_')),
      isEmpty,
      reason: 'occluded home frames must not complete startup points',
    );

    // 数据在遮挡期间完成：内容在层后渲染，测点仍不得完成。
    clock += 100;
    repository.articleRequests.single.complete(
      DataSuccess<PageResult<Article>>(
        PageResult<Article>(items: <Article>[_article], nextPage: null),
      ),
    );
    repository.questionRequests.single.complete(
      DataSuccess<List<Article>>(const <Article>[_question]),
    );
    await tester.pump();
    await tester.pump();
    clock += 100;
    metrics.recordTimings(<FrameTiming>[_timing(clock)]);
    expect(
      events.where((e) => e['point'].toString().startsWith('home_')),
      isEmpty,
      reason:
          'terminal frames behind the startup layer are occluded, not shown',
    );
    expect(
      refPhase(tester),
      isNot(StartupRevealPhase.done),
      reason: 'content is still covered during reveal',
    );

    // 启动层走完揭示与退出：退出后的真实首页帧完成全部测点，
    // 且 startup_layer_exit 先于首页终态。
    await tester.pump(const Duration(milliseconds: 480));
    expect(refPhase(tester), StartupRevealPhase.exiting);
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 500));
    expect(refPhase(tester), StartupRevealPhase.done);
    // The layer-removal frame reported during the exit transition
    // (clock=300); its raster completes at that instant, before the forced
    // rebuild below.
    clock += 10;
    metrics.recordTimings(<FrameTiming>[_timing(clock - 10)]);
    // The layer is gone and no provider changed, so force one post-exit
    // rebuild of the visible home screen (same widget tree, new build) at
    // clock=400; its reports land at requestedAt=400, inside the FrameTiming
    // window below (buildStart=400).
    clock += 100;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: wanTheme(
            palette: WanPalette.slateBlue,
            brightness: Brightness.light,
          ),
          home: StartupRevealLayer(
            child: HomeScreen(
              onArticleTap: (_) {},
              onSearchTap: () {},
              onViewAllQuestions: () {},
            ),
          ),
        ),
      ),
    );
    clock += 10; // Advance to the frame's rasterFinish instant.
    metrics.recordTimings(<FrameTiming>[_timing(clock - 10)]);
    final Map<String, List<Map<String, Object>>> byPoint =
        <String, List<Map<String, Object>>>{};
    for (final Map<String, Object> event in events) {
      byPoint
          .putIfAbsent(event['point']! as String, () => <Map<String, Object>>[])
          .add(event);
    }
    expect(byPoint['startup_layer_exit'], hasLength(1));
    expect(byPoint['home_first_raster'], hasLength(1));
    expect(byPoint['home_articles_raster'], hasLength(1));
    expect(byPoint['home_terminal_raster'], hasLength(1));
    expect(
      byPoint['startup_layer_exit']!.first['dart_us']! as int,
      lessThanOrEqualTo(
        byPoint['home_terminal_raster']!.first['dart_us']! as int,
      ),
      reason: 'the layer exit must not be reported after the content it gated',
    );
  });
}

StartupRevealPhase refPhase(WidgetTester tester) {
  final BuildContext context = tester.element(find.byType(HomeScreen));
  return ProviderScope.containerOf(context).read(startupRevealPhaseProvider);
}

// at = the moment reportStartupFrame ran (build time). The raster must
// finish after the build for the pending point to be accepted.
FrameTiming _timing(int at) => FrameTiming(
  vsyncStart: at - 1,
  buildStart: at,
  buildFinish: at + 1,
  rasterStart: at + 2,
  rasterFinish: at + 10,
  rasterFinishWallTime: at + 10,
);

const Article _article = Article(
  id: 101,
  title: 'article',
  url: 'https://example.com/a',
  author: 'author',
  shareUser: 'shareUser',
  superChapterName: 'chapter',
  chapter: 'chapter',
  publishedAt: '2026-10-01',
  collected: false,
);

const Article _question = Article(
  id: 201,
  title: 'question',
  url: 'https://example.com/q',
  author: 'author',
  shareUser: 'shareUser',
  superChapterName: 'chapter',
  chapter: 'chapter',
  publishedAt: '2026-10-01',
  collected: false,
);

class _ControlledArticleRepository implements ArticleRepository {
  final List<_Pending<PageResult<Article>>> articleRequests =
      <_Pending<PageResult<Article>>>[];
  final List<_Pending<List<Article>>> questionRequests =
      <_Pending<List<Article>>>[];

  @override
  Future<DataResult<PageResult<Article>>> articles(
    int page,
    RequestCancellation cancellation,
  ) {
    final _Pending<PageResult<Article>> request = _Pending<PageResult<Article>>(
      cancellation,
    );
    articleRequests.add(request);
    return request.future;
  }

  @override
  Future<DataResult<List<Article>>> questions(
    RequestCancellation cancellation,
  ) {
    final _Pending<List<Article>> request = _Pending<List<Article>>(
      cancellation,
    );
    questionRequests.add(request);
    return request.future;
  }

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

class _Pending<T> {
  _Pending(this.cancellation);

  final RequestCancellation cancellation;
  final Completer<DataResult<T>> _completer = Completer<DataResult<T>>();

  Future<DataResult<T>> get future => _completer.future;

  void complete(DataResult<T> result) => _completer.complete(result);
}
