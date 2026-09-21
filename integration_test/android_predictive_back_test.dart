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
import 'package:webview_flutter/webview_flutter.dart';

/// Android system back special: cancel and commit phases are driven from the
/// host. The test hosts a small command server on device port 18091; the host
/// reaches it via `adb forward tcp:18091 tcp:18091` and injects raw system
/// gestures with `adb shell input`. Opt in with
/// --dart-define=RUN_SYSTEM_BACK_PHASES=true on a real device or emulator.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('system back cancel keeps page; commit returns in WebView', (
    tester,
  ) async {
    expect(defaultTargetPlatform, TargetPlatform.android);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<!doctype html><h1>Back phases</h1>');
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
            articleId: 111,
            title: 'Back phases',
            url: firstUrl,
            allowLoopbackFixture: true,
            onExit: () => exits++,
            onPopped: () {},
            onControllerReady: (ready) => controller = ready,
          ),
        ),
      ),
    );
    await _waitFor(tester, () async => (await history.page()).length == 1);
    await controller!.loadRequest(Uri.parse(firstUrl).resolve('/second'));
    await _waitFor(
      tester,
      () async =>
          (await controller!.currentUrl())?.endsWith('/second') == true &&
          await controller!.canGoBack(),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final phases = <String, bool>{};
    final commandServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      18091,
    );
    final done = Completer<void>();
    final commands = commandServer.listen((request) async {
      final phase = request.uri.queryParameters['phase'] ?? '';
      Future<Map<String, Object?>> report() async {
        final url = await controller?.currentUrl();
        final canGoBack = await controller?.canGoBack() ?? false;
        return <String, Object?>{
          'url': url,
          'exits': exits,
          'canGoBack': canGoBack,
        };
      }

      Future<void> respond(Object? body, {int status = HttpStatus.ok}) async {
        request.response.headers.contentType = ContentType.json;
        request.response.statusCode = status;
        request.response.write(jsonEncode(body));
        await request.response.close();
      }

      switch (phase) {
        case 'ready':
          await respond(await report());
        case 'assert-cancel':
          final state = await report();
          final url = state['url'] as String?;
          final ok =
              url != null &&
              url.endsWith('/second') &&
              exits == 0 &&
              state['canGoBack'] == true;
          phases['cancel'] = ok;
          await respond(<String, Object?>{'ok': ok}..addAll(state));
        case 'assert-commit':
          final state = await report();
          final url = state['url'] as String?;
          final ok = url != null && url.endsWith('/first') && exits == 0;
          phases['commit'] = ok;
          await respond(<String, Object?>{'ok': ok}..addAll(state));
        case 'done':
          await respond(<String, Object?>{
            'ok': phases['cancel'] == true && phases['commit'] == true,
            'phases': phases,
          });
          if (!done.isCompleted) done.complete();
        default:
          await respond(<String, Object?>{
            'error': 'unknown phase',
          }, status: 400);
      }
    });
    addTearDown(() async {
      await commands.cancel();
      await commandServer.close(force: true);
    });

    await _waitFor(tester, () async {
      try {
        final client = HttpClient();
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:18091/?phase=ready'),
        );
        final response = await request.close();
        await response.drain<void>();
        client.close();
        return response.statusCode == HttpStatus.ok;
      } on Object {
        return false;
      }
    });

    while (!done.isCompleted) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(phases['cancel'], true, reason: 'cancel gesture must keep page 2');
    expect(
      phases['commit'],
      true,
      reason: 'commit gesture must return to page 1',
    );
    expect(exits, 0);
  }, skip: !const bool.fromEnvironment('RUN_SYSTEM_BACK_PHASES'));
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
  fail('Back-phase condition did not occur');
}
