import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wanandroid_stage0_prototypes/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late StreamSubscription<HttpRequest> requests;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requests = server.listen((request) async {
      if (request.uri.path == '/main-500') {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.headers.contentType = ContentType.html;
        request.response.write('<h1>controlled 500</h1>');
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await requests.cancel();
    await server.close(force: true);
  });

  testWidgets('classifies controlled HTTP, subresource, and TLS failures', (
    tester,
  ) async {
    final base = Uri.parse('http://localhost:${server.port}');
    await tester.pumpWidget(
      MaterialApp(home: WebViewProbe(controlledErrorBaseUrl: base)),
    );
    await _waitForText(tester, const Key('status'), 'finished:');

    await _press(tester, const Key('http-main-error'));
    await _waitForAny(tester, const Key('status'), const [
      'failed:',
      'finished:',
      'timedOut',
    ]);
    final httpStatus = _text(tester, const Key('status'));
    final httpTrace = _text(tester, const Key('callback-trace-all'));
    debugPrint('ERROR_PROBE HTTP status=$httpStatus\n$httpTrace');
    expect(httpTrace, contains('http:500'));
    if (defaultTargetPlatform == TargetPlatform.android) {
      expect(httpStatus, contains('failed:http'));
    } else {
      expect(httpTrace, contains('request-url-unavailable'));
    }

    await _press(tester, const Key('subresource-error'));
    await _waitForText(tester, const Key('status'), 'finished:');
    await tester.pump(const Duration(seconds: 1));
    final subresourceStatus = _text(tester, const Key('status'));
    final subresourceDiagnostics = _text(tester, const Key('diagnostics'));
    final subresourceTrace = _text(tester, const Key('callback-trace-all'));
    debugPrint(
      'ERROR_PROBE SUBRESOURCE status=$subresourceStatus '
      'diagnostics=$subresourceDiagnostics\n$subresourceTrace',
    );
    expect(subresourceStatus, contains('finished:'));
    expect(subresourceStatus, isNot(contains('failed:')));
    if (defaultTargetPlatform == TargetPlatform.android) {
      expect(subresourceTrace, contains('http:404'));
      expect(subresourceTrace, contains('request-is-not-main-frame'));
    }

    await _press(tester, const Key('tls-error'));
    await _waitForAny(tester, const Key('status'), const [
      'failed:',
      'timedOut',
    ]);
    final tlsStatus = _text(tester, const Key('status'));
    final tlsTrace = _text(tester, const Key('callback-trace-all'));
    debugPrint('ERROR_PROBE TLS status=$tlsStatus\n$tlsTrace');
    expect(tlsStatus, contains('failed:'));
    expect(tlsTrace, contains('https://localhost:${server.port}/tls'));
  });
}

Future<void> _waitForText(WidgetTester tester, Key key, String fragment) =>
    _waitForAny(tester, key, [fragment]);

Future<void> _waitForAny(
  WidgetTester tester,
  Key key,
  List<String> fragments,
) async {
  for (var attempt = 0; attempt < 120; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    final value = _text(tester, key);
    if (fragments.any(value.contains)) return;
  }
  fail('Timed out waiting for $fragments in ${_text(tester, key)}');
}

String _text(WidgetTester tester, Key key) {
  final widget = tester.widget<Text>(find.byKey(key, skipOffstage: false));
  return widget.data ?? '';
}

Future<void> _press(WidgetTester tester, Key key) async {
  final button = tester.widget<FilledButton>(
    find.byKey(key, skipOffstage: false),
  );
  button.onPressed!.call();
  await tester.pump();
}
