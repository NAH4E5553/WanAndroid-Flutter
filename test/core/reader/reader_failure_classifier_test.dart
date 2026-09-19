import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/reader/reader_failure_classifier.dart';

void main() {
  final mainUrl = Uri.parse('https://example.test/article');
  test('confirmed main resource error fails the full page', () {
    expect(
      ReaderFailureClassifier.resource(
        activeMainUrl: mainUrl,
        callbackUrl: mainUrl,
        isForMainFrame: true,
        kind: ReaderFailureKind.tls,
      ),
      ReaderFailureDisposition.fullPage,
    );
  });

  test('subresource, unknown frame and wrong URL remain diagnostics', () {
    for (final (url, mainFrame) in <(Uri?, bool?)>[
      (Uri.parse('https://example.test/image.png'), false),
      (mainUrl, null),
      (Uri.parse('https://example.test/other'), true),
      (null, true),
    ]) {
      expect(
        ReaderFailureClassifier.resource(
          activeMainUrl: mainUrl,
          callbackUrl: url,
          isForMainFrame: mainFrame,
          kind: ReaderFailureKind.network,
        ),
        ReaderFailureDisposition.diagnostic,
      );
    }
  });

  test('renderer affects current WebView regardless of missing frame URL', () {
    expect(
      ReaderFailureClassifier.resource(
        activeMainUrl: mainUrl,
        callbackUrl: null,
        isForMainFrame: null,
        kind: ReaderFailureKind.renderer,
      ),
      ReaderFailureDisposition.fullPage,
    );
  });

  test('HTTP requires a known matching request URL', () {
    expect(
      ReaderFailureClassifier.http(activeMainUrl: mainUrl, requestUrl: mainUrl),
      ReaderFailureDisposition.fullPage,
    );
    expect(
      ReaderFailureClassifier.http(activeMainUrl: mainUrl, requestUrl: null),
      ReaderFailureDisposition.diagnostic,
    );
    expect(
      ReaderFailureClassifier.http(
        activeMainUrl: mainUrl,
        requestUrl: Uri.parse('https://example.test/image.png'),
      ),
      ReaderFailureDisposition.diagnostic,
    );
  });
}
