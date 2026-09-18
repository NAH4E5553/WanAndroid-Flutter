import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_stage0_prototypes/reader/reader_failure_classifier.dart';

void main() {
  final mainUrl = Uri.parse('https://fixture.invalid/article');

  test('confirmed main-frame network and TLS failures are full-page', () {
    for (final kind in [ReaderFailureKind.network, ReaderFailureKind.tls]) {
      final result = ReaderFailureClassifier.resource(
        activeMainUrl: mainUrl,
        callbackUrl: mainUrl,
        isForMainFrame: true,
        kind: kind,
      );
      expect(result.isFullPage, isTrue);
      expect(result.kind, kind);
    }
  });

  test('subresource and unknown identity stay diagnostic', () {
    for (final mainFrame in [false, null]) {
      final result = ReaderFailureClassifier.resource(
        activeMainUrl: mainUrl,
        callbackUrl: Uri.parse('https://fixture.invalid/image.png'),
        isForMainFrame: mainFrame,
        kind: ReaderFailureKind.network,
      );
      expect(result.isFullPage, isFalse);
    }
    final missingUrl = ReaderFailureClassifier.resource(
      activeMainUrl: mainUrl,
      callbackUrl: null,
      isForMainFrame: true,
      kind: ReaderFailureKind.network,
    );
    expect(missingUrl.isFullPage, isFalse);
  });

  test('renderer termination affects current webview without a URL', () {
    final result = ReaderFailureClassifier.resource(
      activeMainUrl: mainUrl,
      callbackUrl: null,
      isForMainFrame: null,
      kind: ReaderFailureKind.renderer,
    );
    expect(result.isFullPage, isTrue);
  });

  test('HTTP requires request URL to match active main URL', () {
    expect(
      ReaderFailureClassifier.http(
        activeMainUrl: mainUrl,
        requestUrl: mainUrl,
      ).isFullPage,
      isTrue,
    );
    expect(
      ReaderFailureClassifier.http(
        activeMainUrl: mainUrl,
        requestUrl: Uri.parse('https://fixture.invalid/image.png'),
      ).isFullPage,
      isFalse,
    );
    expect(
      ReaderFailureClassifier.http(
        activeMainUrl: mainUrl,
        requestUrl: null,
      ).isFullPage,
      isFalse,
    );
  });
}
