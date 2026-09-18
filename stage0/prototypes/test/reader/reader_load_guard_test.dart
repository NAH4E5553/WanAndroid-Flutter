import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_stage0_prototypes/reader/reader_load_guard.dart';

void main() {
  final url = Uri.parse('https://fixture.invalid/article');

  test('late completion from timed-out same-url load is rejected', () {
    final guard = ReaderLoadGuard();
    final firstBrowser = guard.beginWithNewBrowser(url);
    expect(guard.timeout(firstBrowser), isTrue);

    final retryBrowser = guard.beginWithNewBrowser(url);
    expect(guard.pageFinished(firstBrowser, url), isFalse);
    expect(guard.snapshot.phase, ReaderLoadPhase.loading);
    expect(guard.pageFinished(retryBrowser, url), isTrue);
    expect(guard.snapshot.phase, ReaderLoadPhase.loaded);
    expect(guard.snapshot.ignoredCallbacks, 1);
  });

  test('late error from timed-out same-url load cannot fail current load', () {
    final guard = ReaderLoadGuard();
    final firstBrowser = guard.beginWithNewBrowser(url);
    expect(guard.timeout(firstBrowser), isTrue);
    final retryBrowser = guard.beginWithNewBrowser(url);

    expect(guard.pageFailed(firstBrowser, url), isFalse);
    expect(guard.snapshot.phase, ReaderLoadPhase.loading);
    expect(guard.pageFinished(retryBrowser, url), isTrue);
    expect(guard.snapshot.phase, ReaderLoadPhase.loaded);
  });

  test('completion after timeout on the same browser is conservative', () {
    final guard = ReaderLoadGuard();
    final browser = guard.beginWithNewBrowser(url);
    expect(guard.timeout(browser), isTrue);

    expect(guard.pageFinished(browser, url), isFalse);
    expect(guard.snapshot.phase, ReaderLoadPhase.timedOut);
  });

  test('platform URL binds once for a new browser', () {
    final guard = ReaderLoadGuard();
    final browser = guard.beginWithNewBrowser();
    expect(guard.bindInitialUrl(browser, url), isTrue);
    expect(guard.snapshot.url, url);
    expect(
      guard.bindInitialUrl(browser, Uri.parse('https://fixture.invalid/other')),
      isFalse,
    );
    expect(guard.pageFinished(browser, url), isTrue);
    expect(guard.snapshot.phase, ReaderLoadPhase.loaded);
  });

  test('didPop prevents a second web-history back action', () {
    expect(
      decideReaderBack(didPop: true, webViewCanGoBack: true),
      ReaderBackAction.none,
    );
    expect(
      decideReaderBack(didPop: false, webViewCanGoBack: true),
      ReaderBackAction.webHistoryBack,
    );
  });
}
