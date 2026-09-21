import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wanandroid_flutter/src/core/reader/reading_history_provider.dart';
import 'package:wanandroid_flutter/src/data/database/reading_history_database.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_reading_history_repository.dart';
import 'package:wanandroid_flutter/src/features/reader/view/article_reader_screen.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// iOS edge-back special on a real simulator. The Cupertino page transition
/// implements the iOS back gesture inside Flutter, so tester-level edge drags
/// drive the same code path as a system edge swipe on pushed routes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('edge swipe keeps reader when web history exists', (
    tester,
  ) async {
    expect(defaultTargetPlatform, TargetPlatform.iOS);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<!doctype html><h1>Edge fixture</h1>');
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
    WebViewController? controller;
    var exits = 0;

    await _pushReaderOverHome(
      tester,
      url,
      history,
      (c) => controller = c,
      () => exits++,
    );
    await _waitFor(tester, () async => (await history.page()).length == 1);
    await controller!.loadRequest(Uri.parse(url).resolve('/second'));
    await _waitFor(
      tester,
      () async =>
          (await controller!.currentUrl())?.endsWith('/second') == true &&
          await controller!.canGoBack(),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.dragFrom(const Offset(2, 400), const Offset(300, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ArticleReaderScreen), findsOneWidget);
    expect(find.text('Reader home'), findsNothing);
    expect(
      (await controller!.currentUrl())?.endsWith('/second'),
      true,
      reason: 'a disabled edge gesture must not change the page or exit',
    );
    expect(exits, 0);
  });

  testWidgets('edge swipe exits reader when web history is exhausted', (
    tester,
  ) async {
    expect(defaultTargetPlatform, TargetPlatform.iOS);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<!doctype html><h1>Edge fixture</h1>');
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
    var popped = 0;

    await _pushReaderOverHome(
      tester,
      url,
      history,
      (_) {},
      () => exits++,
      onPopped: () => popped++,
    );
    await _waitFor(tester, () async => (await history.page()).length == 1);

    await tester.dragFrom(const Offset(2, 400), const Offset(300, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ArticleReaderScreen), findsNothing);
    expect(find.text('Reader home'), findsOneWidget);
    expect(popped, 1);
    expect(exits, 0);
  });
}

Future<void> _pushReaderOverHome(
  WidgetTester tester,
  String url,
  DefaultReadingHistoryRepository history,
  ValueChanged<WebViewController> onController,
  VoidCallback onExit, {
  VoidCallback? onPopped,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [readingHistoryRepositoryProvider.overrideWithValue(history)],
      child: MaterialApp(
        home: Scaffold(body: Center(child: Text('Reader home'))),
      ),
    ),
  );
  final context = tester.element(find.text('Reader home'));
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArticleReaderScreen(
          articleId: 131,
          title: 'Edge fixture',
          url: url,
          allowLoopbackFixture: true,
          onExit: onExit,
          onPopped: onPopped ?? () {},
          onControllerReady: onController,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await _waitFor(
    tester,
    () => find.byType(ArticleReaderScreen).evaluate().isNotEmpty,
  );
}

Future<void> _waitFor(
  WidgetTester tester,
  FutureOr<bool> Function() condition, {
  int attempts = 120,
}) async {
  for (var i = 0; i < attempts; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    if (await condition()) return;
  }
  fail('Edge fixture condition did not occur within 12 seconds');
}
