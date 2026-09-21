/// Minimal host-only cookie model for the wanandroid.com session jar.
///
/// Deliberately narrow: only cookies whose domain equals the API host are
/// accepted, so cross-domain handling is out of scope by contract.
class WebCookie {
  const WebCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.expiresAtMilliseconds,
    required this.persistent,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final int expiresAtMilliseconds;
  final bool persistent;

  DateTime get expiresAt =>
      DateTime.fromMillisecondsSinceEpoch(expiresAtMilliseconds, isUtc: true);

  bool get expired =>
      expiresAtMilliseconds <= DateTime.now().toUtc().millisecondsSinceEpoch;

  bool matches(Uri url) => url.path.startsWith(path.isEmpty ? '/' : path);

  String toHeader() => '$name=$value';

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'value': value,
    'domain': domain,
    'path': path,
    'expiresAt': expiresAtMilliseconds,
    'persistent': persistent,
  };

  static WebCookie? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final Object? name = json['name'];
    final Object? value = json['value'];
    final Object? domain = json['domain'];
    final Object? path = json['path'];
    final Object? expiresAt = json['expiresAt'];
    final Object? persistent = json['persistent'];
    if (name is! String ||
        value is! String ||
        domain is! String ||
        path is! String ||
        expiresAt is! int ||
        persistent is! bool) {
      return null;
    }
    return WebCookie(
      name: name,
      value: value,
      domain: domain,
      path: path,
      expiresAtMilliseconds: expiresAt,
      persistent: persistent,
    );
  }

  /// Parses one Set-Cookie header value. Returns null for cookies that do not
  /// belong to the API host or cannot be represented by this model.
  static WebCookie? parse(String header, {required String apiHost}) {
    final List<String> segments = header.split(';');
    if (segments.isEmpty) {
      return null;
    }
    final int equals = segments.first.indexOf('=');
    if (equals <= 0) {
      return null;
    }
    final String name = segments.first.substring(0, equals).trim();
    final String value = segments.first.substring(equals + 1).trim();
    if (name.isEmpty || name.toLowerCase() == 'expires') {
      return null;
    }
    String domain = apiHost;
    String path = '/';
    int? expiresAt;
    int? maxAge;
    for (final String rawAttribute in segments.skip(1)) {
      final int split = rawAttribute.indexOf('=');
      final String attributeName =
          (split <= 0 ? rawAttribute : rawAttribute.substring(0, split))
              .trim()
              .toLowerCase();
      final String attributeValue = split <= 0
          ? ''
          : rawAttribute.substring(split + 1).trim();
      switch (attributeName) {
        case 'domain':
          final String normalized = attributeValue.toLowerCase().startsWith('.')
              ? attributeValue.substring(1)
              : attributeValue.toLowerCase();
          if (normalized != apiHost) {
            return null;
          }
          domain = apiHost;
        case 'path':
          if (attributeValue.startsWith('/')) {
            path = attributeValue;
          }
        case 'max-age':
          maxAge = int.tryParse(attributeValue);
        case 'expires':
          expiresAt = _parseHttpDate(attributeValue);
      }
    }
    if (maxAge != null) {
      if (maxAge <= 0) {
        return null;
      }
      expiresAt = DateTime.now()
          .toUtc()
          .add(Duration(seconds: maxAge))
          .millisecondsSinceEpoch;
    }
    final bool persistent = expiresAt != null || (maxAge ?? 0) > 0;
    final int expires = expiresAt ?? 0;
    if (persistent && expires <= 0) {
      return null;
    }
    return WebCookie(
      name: name,
      value: value,
      domain: domain,
      path: path,
      expiresAtMilliseconds: expires,
      persistent: persistent,
    );
  }

  /// Parses the RFC 1123 date format servers use for Expires
  /// ("Wed, 21 Oct 2015 07:28:00 GMT").
  static int? _parseHttpDate(String value) {
    final RegExpMatch? match = RegExp(
      r'(\d{1,2}) ([A-Za-z]{3}) (\d{2,4}) (\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(value);
    if (match == null) {
      return null;
    }
    const Map<String, int> months = <String, int>{
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final int? month = months[match.group(2)!.toLowerCase()];
    if (month == null) {
      return null;
    }
    final int day = int.parse(match.group(1)!);
    int year = int.parse(match.group(3)!);
    if (year < 100) {
      year += year < 70 ? 2000 : 1900;
    }
    final DateTime utc = DateTime.utc(
      year,
      month,
      day,
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
    return utc.millisecondsSinceEpoch;
  }
}
