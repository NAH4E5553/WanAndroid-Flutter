import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/reader/reader_url_policy.dart';

void main() {
  test('only official relative blog paths are resolved', () {
    expect(
      ReaderUrlPolicy.articleUrl('/blog/show/123?from=x#part').toString(),
      'https://wanandroid.com/blog/show/123?from=x#part',
    );
    expect(ReaderUrlPolicy.articleUrl('//evil.test/blog/show/123'), isNull);
    expect(ReaderUrlPolicy.articleUrl('/other/123'), isNull);
    expect(ReaderUrlPolicy.articleUrl('/blog/show/x'), isNull);
    expect(ReaderUrlPolicy.articleUrl('http://example.test/a'), isNull);
  });

  test('scheme and authority policy blocks dangerous navigation', () {
    expect(
      ReaderUrlPolicy.classify(Uri.parse('https://example.test/a')),
      ReaderUrlAction.inApp,
    );
    expect(
      ReaderUrlPolicy.classify(Uri.parse('http://example.test/a')),
      ReaderUrlAction.confirmExternal,
    );
    expect(
      ReaderUrlPolicy.classify(Uri.parse('mailto:someone@example.test')),
      ReaderUrlAction.confirmExternal,
    );
    expect(
      ReaderUrlPolicy.classify(Uri.parse('https://user@example.test/a')),
      ReaderUrlAction.block,
    );
    expect(
      ReaderUrlPolicy.classify(Uri.parse('https://example.test:8443/a')),
      ReaderUrlAction.block,
    );
    expect(
      ReaderUrlPolicy.classify(Uri.parse('javascript:alert(1)')),
      ReaderUrlAction.block,
    );
    expect(ReaderUrlPolicy.articleUrl('https://example.test/%0a'), isNull);
  });

  test('history canonicalization strips fragment but preserves query', () {
    expect(
      ReaderUrlPolicy.canonicalHistoryUrl('https://EXAMPLE.test:443/A?q=1#x')
          .toString(),
      'https://example.test/A?q=1',
    );
    expect(
      ReaderUrlPolicy.canonicalHistoryUrl('https://example.test/A?q=2')
          .toString(),
      'https://example.test/A?q=2',
    );
    expect(
      ReaderUrlPolicy.canonicalHistoryUrl('https://example.test?q=1')
          .toString(),
      'https://example.test/?q=1',
    );
  });
}
