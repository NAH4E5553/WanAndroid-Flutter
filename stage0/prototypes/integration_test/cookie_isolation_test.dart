import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wanandroid_stage0_prototypes/session/api_cookie_isolation.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late StreamSubscription<HttpRequest> requests;
  late Completer<String?> observedReaderCookie;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requests = server.listen((request) async {
      if (request.uri.path == '/reader') {
        if (!observedReaderCookie.isCompleted) {
          observedReaderCookie.complete(request.headers.value('cookie'));
        }
        request.response.headers.contentType = ContentType.html;
        request.response.write('<!doctype html><h1>controlled reader</h1>');
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

  setUp(() {
    observedReaderCookie = Completer<String?>();
  });

  testWidgets('real WebView request carries only its reader-domain cookie', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 9, 18, 12);
    final apiStore = ApiCookieIsolationStore()..activateSession('fixture-a');
    final apiRequest = apiStore.capture(
      Uri.parse('https://wanandroid.com/user/login'),
      now: now,
    );
    expect(
      apiStore.acceptSetCookie(
        apiRequest,
        'api_session=fixture-a; Path=/; Secure; Max-Age=60',
        now: now,
      ),
      isTrue,
    );
    expect(
      apiStore.capture(ApiCookieIsolationStore.apiBase, now: now).cookieHeader,
      contains('api_session='),
    );

    final cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();
    addTearDown(cookieManager.clearCookies);
    await cookieManager.setCookie(
      const WebViewCookie(
        name: 'reader_fixture',
        value: 'visible',
        domain: 'localhost',
        path: '/',
      ),
    );

    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.disabled);
    final finished = Completer<void>();
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!finished.isCompleted) finished.complete();
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WebViewWidget(controller: controller)),
      ),
    );
    final readerUri = Uri.parse('http://localhost:${server.port}/reader');
    await controller.loadRequest(readerUri);

    final header = await observedReaderCookie.future.timeout(
      const Duration(seconds: 10),
    );
    await finished.future.timeout(const Duration(seconds: 10));
    expect(header, contains('reader_fixture=visible'));
    expect(header, isNot(contains('api_session')));

    final webViewCookies = await cookieManager.getCookies(domain: readerUri);
    expect(
      webViewCookies.map((cookie) => cookie.name),
      contains('reader_fixture'),
    );
    expect(
      webViewCookies.map((cookie) => cookie.name),
      isNot(contains('api_session')),
    );
  });
}
