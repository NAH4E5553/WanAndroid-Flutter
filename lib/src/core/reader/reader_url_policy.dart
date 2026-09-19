enum ReaderUrlAction { inApp, confirmExternal, block }

class ReaderUrlPolicy {
  const ReaderUrlPolicy._();

  static final RegExp _officialBlog = RegExp(
    r'^/?blog/show/[0-9]+/?$',
    caseSensitive: false,
  );

  static Uri? articleUrl(String raw, {bool allowLoopbackFixture = false}) {
    raw = raw.trim();
    if (_unsafe(raw)) return null;
    final Uri? parsed = Uri.tryParse(raw);
    if (parsed == null) return null;
    if (parsed.hasScheme) {
      return classify(parsed, allowLoopbackFixture: allowLoopbackFixture) ==
              ReaderUrlAction.inApp
          ? parsed
          : null;
    }
    if (raw.startsWith('//') || !_officialBlog.hasMatch(parsed.path)) {
      return null;
    }
    return Uri.parse('https://wanandroid.com/').resolve(raw);
  }

  static ReaderUrlAction classify(
    Uri uri, {
    bool allowLoopbackFixture = false,
  }) {
    final String raw = uri.toString();
    if (_unsafe(raw) || uri.userInfo.isNotEmpty) return ReaderUrlAction.block;
    if (allowLoopbackFixture &&
        !const bool.fromEnvironment('dart.vm.product') &&
        uri.scheme == 'http' &&
        uri.host == 'localhost') {
      return ReaderUrlAction.inApp;
    }
    if (uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        (!uri.hasPort || uri.port == 443)) {
      return ReaderUrlAction.inApp;
    }
    if (uri.scheme == 'http' ||
        uri.scheme == 'tel' ||
        uri.scheme == 'mailto' ||
        uri.scheme == 'geo') {
      return ReaderUrlAction.confirmExternal;
    }
    return ReaderUrlAction.block;
  }

  static Uri? canonicalHistoryUrl(
    String raw, {
    bool allowLoopbackFixture = false,
  }) {
    if (_unsafe(raw)) return null;
    final Uri? uri = Uri.tryParse(raw);
    if (uri == null ||
        classify(uri, allowLoopbackFixture: allowLoopbackFixture) !=
            ReaderUrlAction.inApp) {
      return null;
    }
    final Uri withoutFragment = Uri.parse(uri.toString().split('#').first);
    final String normalized = withoutFragment.toString();
    if (withoutFragment.path.isNotEmpty) return withoutFragment;
    final int query = normalized.indexOf('?');
    return Uri.parse(
      query < 0
          ? '$normalized/'
          : '${normalized.substring(0, query)}/${normalized.substring(query)}',
    );
  }

  static bool samePage(Uri left, Uri right) =>
      left.toString().split('#').first == right.toString().split('#').first;

  static bool _unsafe(String raw) =>
      raw.isEmpty ||
      raw.length > 8192 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(raw) ||
      RegExp(r'%(?:0[ad]|1[0-9]|7f)', caseSensitive: false).hasMatch(raw);
}
