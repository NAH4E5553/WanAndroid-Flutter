import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wanandroid_flutter/src/app/app.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/diagnostics/startup_metrics.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/startup/startup_reveal_controller.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

import '../test/support/fake_avatar_dependencies.dart';
import '../test/support/fake_session_repositories.dart';
import '../test/support/fixed_topic_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real engine blends the whole layer then reports visible home', (
    WidgetTester tester,
  ) async {
    final StartupMetrics previous = StartupMetrics.instance;
    final List<Map<String, Object>> events = <Map<String, Object>>[];
    final StartupMetrics metrics =
        StartupMetrics(enabled: true, emit: events.add)
          ..start()
          ..attach();
    StartupMetrics.instance = metrics;
    final List<Map<String, int>> timingReports = <Map<String, int>>[];
    void observeTimings(List<ui.FrameTiming> timings) {
      for (final ui.FrameTiming frame in timings) {
        timingReports.add(<String, int>{
          'build_start': frame.timestampInMicroseconds(
            ui.FramePhase.buildStart,
          ),
          'build_finish': frame.timestampInMicroseconds(
            ui.FramePhase.buildFinish,
          ),
          'raster_finish': frame.timestampInMicroseconds(
            ui.FramePhase.rasterFinish,
          ),
          'callback_now': metrics.debugNow,
        });
      }
    }

    SchedulerBinding.instance.addTimingsCallback(observeTimings);
    final _ControlledArticleRepository repository =
        _ControlledArticleRepository();
    // A cold Debug build can spend seconds compiling its first app frame.
    // Extend only this fixture's observation window so sampling is independent
    // of that cost; production defaults stay covered by the unmodified tests.
    final StartupRevealController controller = StartupRevealController(
      revealDuration: const Duration(seconds: 10),
      exitDuration: const Duration(seconds: 1),
    );
    final ProviderContainer container = ProviderContainer(
      overrides: [
        startupRevealControllerProvider.overrideWithValue(controller),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        avatarRepositoryProvider.overrideWithValue(FakeAvatarRepository()),
        collectionRepositoryProvider.overrideWithValue(
          FakeCollectionRepository(),
        ),
        articleRepositoryProvider.overrideWithValue(repository),
        topicRepositoryProvider.overrideWithValue(const FixedTopicRepository()),
      ],
    );
    const Key captureKey = ValueKey<String>('engine-startup-capture');
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    final Directory artifacts = await getTemporaryDirectory();
    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: UncontrolledProviderScope(
            container: container,
            child: const WanAndroidApp(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.phase, StartupRevealPhase.revealing);
      expect(
        repository.articleRequested && repository.questionRequested,
        isTrue,
      );
      expect(events.where((e) => e['point'] == 'home_first_raster'), isEmpty);

      repository.article.complete(
        const DataSuccess<PageResult<Article>>(
          PageResult<Article>(items: <Article>[_article], nextPage: null),
        ),
      );
      repository.question.complete(
        const DataSuccess<List<Article>>(<Article>[_article]),
      );
      await tester.pump();
      await tester.pump();
      expect(controller.phase, StartupRevealPhase.exiting);
      final Finder fade = find.descendant(
        of: find.byKey(const ValueKey<String>('startup-overlay')),
        matching: find.byType(Opacity),
      );
      double opacity = 1;
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        opacity = tester.widget<Opacity>(fade).opacity;
        if (opacity > 0 && opacity < 1) break;
      }
      expect(opacity, inExclusiveRange(0.0, 1.0));
      expect(
        events.where((e) => e['point'] == 'home_terminal_raster'),
        isEmpty,
      );
      final RenderRepaintBoundary boundary = tester.renderObject(
        find.byKey(captureKey),
      );
      final int? mixedGreen = await tester.runAsync(() async {
        final ui.Image image = await boundary.toImage();
        try {
          final rgba = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          // Bottom navigation has a white background with dark fixture text.
          // At least one dark glyph pixel must be lightened by the white
          // splash background while both the fade and target are present.
          final int startY = image.height * 9 ~/ 10;
          int minGreen = 255;
          for (int y = startY; y < image.height; y += 2) {
            for (int x = 0; x < image.width; x += 2) {
              final int green = rgba!.getUint8((y * image.width + x) * 4 + 1);
              if (green < minGreen) minGreen = green;
            }
          }
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${artifacts.path}/startup_review_fifth_blend.png')
              .writeAsBytes(
                png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
              );
          return minGreen;
        } finally {
          image.dispose();
        }
      });
      expect(mixedGreen, inExclusiveRange(0, 255));
      expect(mixedGreen, greaterThanOrEqualTo((opacity * 255).floor() - 2));
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (events.any((e) => e['point'] == 'home_terminal_raster')) break;
      }
      expect(controller.isDone, isTrue);
      expect(
        find.byKey(const ValueKey<String>('startup-overlay')),
        findsNothing,
      );
      expect(
        events.where((e) => e['point'] == 'startup_layer_exit'),
        hasLength(1),
        reason:
            'Actual engine events: ${jsonEncode(events)}; '
            'pending=${metrics.pendingCount}; frames=${timingReports.length}; '
            'first=${timingReports.take(2).toList()}',
      );
      int time(String point) =>
          events.singleWhere((e) => e['point'] == point)['dart_us']! as int;
      final int exit = time('startup_layer_exit');
      expect(time('home_first_raster'), greaterThanOrEqualTo(exit));
      expect(time('home_articles_raster'), greaterThanOrEqualTo(exit));
      expect(time('home_terminal_raster'), greaterThanOrEqualTo(exit));
      expect(find.text('startup fixture article'), findsWidgets);
      // Only fixed fixture pixels and diagnostic times; no bootstrap, HTTP,
      // persistent session, or account data is accessed by this host.
      // ignore: avoid_print
      print(
        'STARTUP_FAKE_ENGINE ${jsonEncode(<String, Object?>{'blend_opacity': opacity, 'blend_min_green': mixedGreen, 'artifact': '${artifacts.path}/startup_review_fifth_blend.png', 'points': events})}',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      controller.dispose();
      metrics.detach();
      SchedulerBinding.instance.removeTimingsCallback(observeTimings);
      StartupMetrics.instance = previous;
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    }
  });
}

class _ControlledArticleRepository implements ArticleRepository {
  final Completer<DataResult<PageResult<Article>>> article = Completer();
  final Completer<DataResult<List<Article>>> question = Completer();
  bool articleRequested = false;
  bool questionRequested = false;
  @override
  Future<DataResult<PageResult<Article>>> articles(
    int page,
    RequestCancellation cancellation,
  ) {
    articleRequested = true;
    return article.future;
  }

  @override
  Future<DataResult<List<Article>>> questions(
    RequestCancellation cancellation,
  ) {
    questionRequested = true;
    return question.future;
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

const Article _article = Article(
  id: 101,
  title: 'startup fixture article',
  url: 'https://fixture.invalid/startup',
  author: 'fixture author',
  shareUser: '',
  superChapterName: 'fixture chapter',
  chapter: 'fixture',
  publishedAt: '2026-10-02',
  collected: false,
);
