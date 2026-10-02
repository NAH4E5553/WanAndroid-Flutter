import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/diagnostics/startup_metrics.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/features/home/view/home_screen.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real engine correlates visible home with its raster frame', (
    WidgetTester tester,
  ) async {
    final StartupMetrics previous = StartupMetrics.instance;
    final List<Map<String, Object>> events = <Map<String, Object>>[];
    final StartupMetrics metrics =
        StartupMetrics(enabled: true, emit: events.add)
          ..start()
          ..attach();
    StartupMetrics.instance = metrics;
    addTearDown(() {
      metrics.detach();
      StartupMetrics.instance = previous;
    });
    final _Repository repository = _Repository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [articleRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: wanTheme(
            palette: WanPalette.slateBlue,
            brightness: Brightness.light,
          ),
          home: Scaffold(
            body: HomeScreen(
              onArticleTap: (_) {},
              onSearchTap: () {},
              onViewAllQuestions: () {},
            ),
          ),
        ),
      ),
    );
    Future<void> waitFor(String point) async {
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (events.any((event) => event['point'] == point)) return;
      }
      fail('Missing engine measurement: $point; events=$events');
    }

    await waitFor('home_first_raster');
    expect(events.any((e) => e['point'] == 'home_content_raster'), isFalse);
    repository.article.complete(
      const DataSuccess<PageResult<Article>>(
        PageResult<Article>(items: <Article>[], nextPage: null),
      ),
    );
    await waitFor('home_articles_raster');
    expect(events.any((e) => e['point'] == 'home_content_raster'), isFalse);
    repository.question.complete(const DataSuccess<List<Article>>(<Article>[]));
    await waitFor('home_content_raster');
    final Map<String, Object> content = events.singleWhere(
      (e) => e['point'] == 'home_content_raster',
    );
    expect(content['outcome'], 'empty');
    expect(content['dart_us'], greaterThan(0));
    expect(
      (content['epoch_us']! as int) - DateTime.now().microsecondsSinceEpoch,
      lessThanOrEqualTo(0),
    );
    expect(
      events.singleWhere(
        (e) => e['point'] == 'home_articles_raster',
      )['dart_us'],
      lessThan(content['dart_us']! as int),
    );
  });
}

class _Repository implements ArticleRepository {
  final Completer<DataResult<PageResult<Article>>> article =
      Completer<DataResult<PageResult<Article>>>();
  final Completer<DataResult<List<Article>>> question =
      Completer<DataResult<List<Article>>>();
  @override
  Future<DataResult<PageResult<Article>>> articles(
    int page,
    RequestCancellation cancellation,
  ) => article.future;
  @override
  Future<DataResult<List<Article>>> questions(
    RequestCancellation cancellation,
  ) => question.future;
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
