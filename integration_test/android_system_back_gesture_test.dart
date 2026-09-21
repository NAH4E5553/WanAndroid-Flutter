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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Opt in with --dart-define=RUN_NATIVE_BACK_GESTURE=true on an Android device.
  // After NATIVE_BACK_READY, inject a real system edge swipe from outside Flutter.
  testWidgets('Android system edge swipe returns within WebView', (
    tester,
  ) async {
    expect(defaultTargetPlatform, TargetPlatform.android);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<!doctype html><h1>Gesture fixture</h1>');
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

    final firstUrl = 'http://localhost:${server.port}/first';
    WebViewController? controller;
    var exits = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readingHistoryRepositoryProvider.overrideWithValue(history),
        ],
        child: MaterialApp(
          home: ArticleReaderScreen(
            articleId: 101,
            title: 'Gesture fixture',
            url: firstUrl,
            allowLoopbackFixture: true,
            onExit: () => exits++,
            onPopped: () {},
            onControllerReady: (ready) => controller = ready,
          ),
        ),
      ),
    );
    await _waitFor(tester, () => controller != null);
    await _waitFor(tester, () async => (await history.page()).length == 1);
    await controller!.loadRequest(Uri.parse(firstUrl).resolve('/second'));
    await _waitFor(
      tester,
      () async =>
          (await controller!.currentUrl())?.endsWith('/second') == true &&
          await controller!.canGoBack(),
    );
    await tester.pump(const Duration(milliseconds: 300));
    debugPrint('NATIVE_BACK_READY');
    await _waitFor(
      tester,
      () async => (await controller!.currentUrl())?.endsWith('/first') == true,
      attempts: 600,
    );
    expect(exits, 0);
  }, skip: !const bool.fromEnvironment('RUN_NATIVE_BACK_GESTURE'));
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
  fail('Native gesture condition did not occur');
}
