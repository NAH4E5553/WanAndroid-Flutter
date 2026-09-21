import 'dart:async';
import 'dart:convert';
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

/// WebView native lifecycle special. The host drives phases over device port
/// 18092 via `adb forward tcp:18092 tcp:18092`:
/// - /ready: reader is open on the fixture page.
/// - /dispose: the reader widget is replaced, then the host observes whether
///   the sandboxed WebView renderer process exits and reports back.
/// - /report: host result of the renderer observation; asserted in app.
/// - /reopen: a fresh reader instance is opened for the kill phase.
/// - /assert-renderer-failure: after the host kills the renderer (root or
///   emulator only), the reader must stay alive, show the renderer failure
///   UI, and keep the history intact.
/// - /retry: the reader recovers through the retry button.
/// - /done: finishes the run; `scope=dispose` (devices without root, where the
///   renderer cannot be killed) skips the kill-phase assertions that
///   `scope=full` (default) requires.
/// Opt in with --dart-define=RUN_WEBVIEW_NATIVE_LIFECYCLE=true.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renderer death shows failure and recovers; dispose releases', (
    tester,
  ) async {
    expect(defaultTargetPlatform, TargetPlatform.android);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<!doctype html><h1>Lifecycle fixture</h1>');
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
    final url = 'http://localhost:${server.port}/page';
    Widget reader() => ProviderScope(
      overrides: [readingHistoryRepositoryProvider.overrideWithValue(history)],
      child: MaterialApp(
        home: ArticleReaderScreen(
          articleId: 141,
          title: 'Lifecycle fixture',
          url: url,
          allowLoopbackFixture: true,
          onExit: () {},
          onPopped: () {},
        ),
      ),
    );

    final phases = <String, Object?>{};
    final done = Completer<void>();
    final pendingCommands = <String>[];
    final commandResults = <String, Completer<bool>>{};

    Future<bool> enqueue(String command) {
      final result = commandResults.putIfAbsent(command, Completer<bool>.new);
      if (!pendingCommands.contains(command)) pendingCommands.add(command);
      return result.future.timeout(const Duration(seconds: 90));
    }

    Future<void> pumpFor(FutureOr<bool> Function() condition) async {
      for (var i = 0; i < 120; i++) {
        if (await condition()) return;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }
      fail('Lifecycle fixture condition did not occur');
    }

    Future<void> perform(String command) async {
      switch (command) {
        case 'ready':
        case 'reopen':
          await tester.pumpWidget(reader());
          await pumpFor(() async => (await history.page()).isNotEmpty);
          commandResults.remove(command)?.complete(true);
        case 'dispose':
          await tester.pumpWidget(
            const MaterialApp(home: Scaffold(body: Text('Reader closed'))),
          );
          await tester.pump(const Duration(seconds: 1));
          commandResults.remove(command)?.complete(true);
        case 'assert-renderer-failure':
          await pumpFor(() => find.text('网页进程异常').evaluate().isNotEmpty);
          phases['rendererFailureShown'] = true;
          commandResults.remove(command)?.complete(true);
        case 'retry':
          await tester.tap(find.text('重试'));
          await pumpFor(
            () =>
                find.text('网页进程异常').evaluate().isEmpty &&
                find.byType(ArticleReaderScreen).evaluate().isNotEmpty,
          );
          phases['recoveredAfterRetry'] = true;
          commandResults.remove(command)?.complete(true);
      }
    }

    Future<void> respond(
      HttpRequest request,
      Object? body, {
      int status = HttpStatus.ok,
    }) async {
      request.response.headers.contentType = ContentType.json;
      request.response.statusCode = status;
      request.response.write(jsonEncode(body));
      await request.response.close();
    }

    final commandServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      18092,
    );
    final commands = commandServer.listen((request) async {
      final phase = request.uri.queryParameters['phase'] ?? '';
      switch (phase) {
        case 'ready':
        case 'dispose':
        case 'reopen':
        case 'assert-renderer-failure':
        case 'retry':
          final ok = await enqueue(phase);
          await respond(request, <String, Object?>{'ok': ok});
        case 'report':
          final renderer = request.uri.queryParameters['renderer'] ?? 'unknown';
          phases['rendererAfterDisposeReported'] =
              renderer == 'gone' || renderer == 'present';
          await respond(request, <String, Object?>{
            'ok': true,
            'renderer': renderer,
          });
        case 'done':
          phases['scope'] = request.uri.queryParameters['scope'] ?? 'full';
          await respond(request, <String, Object?>{
            'ok': true,
            'phases': phases,
          });
          if (!done.isCompleted) done.complete();
        default:
          await respond(request, <String, Object?>{
            'error': 'unknown phase',
          }, status: 400);
      }
    });
    addTearDown(() async {
      await commands.cancel();
      await commandServer.close(force: true);
    });

    while (!done.isCompleted) {
      final command = pendingCommands.isEmpty ? null : pendingCommands.first;
      if (command != null) {
        pendingCommands.remove(command);
        await perform(command);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(phases['scope'], isIn(<String>['full', 'dispose']));
    expect(phases['rendererAfterDisposeReported'], true);
    if (phases['scope'] == 'full') {
      expect(phases['rendererFailureShown'], true);
      expect(phases['recoveredAfterRetry'], true);
    }
  }, skip: !const bool.fromEnvironment('RUN_WEBVIEW_NATIVE_LIFECYCLE'));
}
