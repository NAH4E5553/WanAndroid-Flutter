import 'dart:io';

final class ApiSessionRequest {
  const ApiSessionRequest._({
    required this.generation,
    required this.uri,
    required this.cookieHeader,
  });

  final int generation;
  final Uri uri;
  final String? cookieHeader;
}

final class ApiCookieSnapshot {
  const ApiCookieSnapshot({
    required this.generation,
    required this.accountId,
    required this.cookieCount,
  });

  final int generation;
  final String? accountId;
  final int cookieCount;
}

/// Stage-0 API-cookie authority. It deliberately has no dependency on the
/// WebView cookie manager and never exposes cookie values in diagnostics.
final class ApiCookieIsolationStore {
  static final Uri apiBase = Uri.parse('https://wanandroid.com/');

  int _generation = 0;
  String? _accountId;
  final Map<String, _StoredApiCookie> _cookies = {};

  ApiCookieSnapshot get snapshot => ApiCookieSnapshot(
    generation: _generation,
    accountId: _accountId,
    cookieCount: _cookies.length,
  );

  int activateSession(String accountId) {
    if (accountId.isEmpty) throw ArgumentError.value(accountId, 'accountId');
    _generation++;
    _accountId = accountId;
    _cookies.clear();
    return _generation;
  }

  int clearSession() {
    _generation++;
    _accountId = null;
    _cookies.clear();
    return _generation;
  }

  ApiSessionRequest capture(Uri uri, {required DateTime now}) {
    _purgeExpired(now);
    return ApiSessionRequest._(
      generation: _generation,
      uri: uri,
      cookieHeader: _cookieHeaderFor(uri, now),
    );
  }

  bool acceptSetCookie(
    ApiSessionRequest request,
    String setCookie, {
    required DateTime now,
  }) {
    if (_accountId == null || request.generation != _generation) return false;
    if (!_isApiUri(request.uri)) return false;
    final parsed = _parse(setCookie, request.uri, now);
    if (parsed == null) return false;
    if (parsed.isExpiredAt(now)) {
      _cookies.remove(parsed.key);
      return true;
    }
    _cookies[parsed.key] = parsed;
    return true;
  }

  String? _cookieHeaderFor(Uri uri, DateTime now) {
    if (_accountId == null || !_isApiUri(uri)) return null;
    final matches =
        _cookies.values.where((cookie) => cookie.matches(uri, now)).toList()
          ..sort((a, b) => b.path.length.compareTo(a.path.length));
    if (matches.isEmpty) return null;
    return matches.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }

  bool _isApiUri(Uri uri) =>
      uri.scheme == apiBase.scheme &&
      uri.host == apiBase.host &&
      uri.port == apiBase.port &&
      uri.userInfo.isEmpty;

  void _purgeExpired(DateTime now) {
    _cookies.removeWhere((_, cookie) => cookie.isExpiredAt(now));
  }

  _StoredApiCookie? _parse(String source, Uri responseUri, DateTime now) {
    final parts = source.split(';');
    if (parts.isEmpty) return null;
    final pair = parts.first.trim();
    final separator = pair.indexOf('=');
    if (separator <= 0) return null;
    final name = pair.substring(0, separator).trim();
    final value = pair.substring(separator + 1).trim();
    if (!_validToken(name) || value.contains(RegExp(r'[\r\n;]'))) return null;

    var domain = responseUri.host;
    var hostOnly = true;
    var path = _defaultPath(responseUri.path);
    var secure = false;
    DateTime? expiresAt;
    for (final rawAttribute in parts.skip(1)) {
      final attribute = rawAttribute.trim();
      if (attribute.isEmpty) continue;
      final equals = attribute.indexOf('=');
      final attributeName =
          (equals < 0 ? attribute : attribute.substring(0, equals))
              .trim()
              .toLowerCase();
      final attributeValue = equals < 0
          ? ''
          : attribute.substring(equals + 1).trim();
      switch (attributeName) {
        case 'domain':
          final candidate = attributeValue.toLowerCase().replaceFirst(
            RegExp(r'^\.'),
            '',
          );
          if (candidate.isEmpty ||
              !_domainMatches(responseUri.host, candidate)) {
            return null;
          }
          domain = candidate;
          hostOnly = false;
        case 'path':
          if (attributeValue.startsWith('/')) path = attributeValue;
        case 'secure':
          secure = true;
        case 'max-age':
          final seconds = int.tryParse(attributeValue);
          if (seconds == null) return null;
          expiresAt = seconds <= 0 ? now : now.add(Duration(seconds: seconds));
        case 'expires':
          if (expiresAt == null) {
            try {
              expiresAt = HttpDate.parse(attributeValue).toUtc();
            } on FormatException {
              return null;
            }
          }
      }
    }
    return _StoredApiCookie(
      name: name,
      value: value,
      domain: domain,
      hostOnly: hostOnly,
      path: path,
      secure: secure,
      expiresAt: expiresAt,
    );
  }

  static bool _validToken(String value) =>
      value.isNotEmpty &&
      !value.contains(RegExp(r'[()<>@,;:\\"/\[\]?={}\s\x00-\x1f\x7f]'));

  static bool _domainMatches(String host, String domain) =>
      host == domain || host.endsWith('.$domain');

  static String _defaultPath(String requestPath) {
    if (!requestPath.startsWith('/') || requestPath == '/') return '/';
    final lastSlash = requestPath.lastIndexOf('/');
    return lastSlash <= 0 ? '/' : requestPath.substring(0, lastSlash);
  }
}

final class _StoredApiCookie {
  const _StoredApiCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.hostOnly,
    required this.path,
    required this.secure,
    required this.expiresAt,
  });

  final String name;
  final String value;
  final String domain;
  final bool hostOnly;
  final String path;
  final bool secure;
  final DateTime? expiresAt;

  String get key => '$name\n$domain\n$path';

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now);

  bool matches(Uri uri, DateTime now) {
    if (isExpiredAt(now) || (secure && uri.scheme != 'https')) return false;
    final domainMatches = hostOnly
        ? uri.host == domain
        : ApiCookieIsolationStore._domainMatches(uri.host, domain);
    return domainMatches && _pathMatches(uri.path, path);
  }

  static bool _pathMatches(String requestPath, String cookiePath) {
    if (requestPath == cookiePath) return true;
    if (!requestPath.startsWith(cookiePath)) return false;
    return cookiePath.endsWith('/') ||
        (requestPath.length > cookiePath.length &&
            requestPath[cookiePath.length] == '/');
  }
}
