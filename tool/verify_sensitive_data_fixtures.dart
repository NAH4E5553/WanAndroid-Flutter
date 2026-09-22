import 'dart:io';

import 'verify_sensitive_data.dart';

void main() {
  final Map<String, String?> expectations = <String, String?>{
    'sensitive_data_pass': null,
    'sensitive_data_phone_violation': 'REAL_IDENTITY_LITERAL',
    'sensitive_data_cookie_violation': 'NUMERIC_LOGIN_COOKIE',
    'sensitive_data_log_violation': 'AUTH_CONSOLE_LOG',
  };
  final List<String> failures = <String>[];
  for (final MapEntry<String, String?> entry in expectations.entries) {
    final Directory fixture = Directory(
      Directory.current.uri
          .resolve('tool/test_fixtures/${entry.key}/')
          .toFilePath(),
    );
    final Directory workspace = Directory.systemTemp.createTempSync(
      'wanandroid_sensitive_data_',
    );
    try {
      _copyFixture(fixture, workspace);
      final SensitiveDataReport report = SensitiveDataVerifier(workspace)
          .verify();
      final String? expectedRule = entry.value;
      if (expectedRule == null && report.violations.isNotEmpty) {
        failures.add('${entry.key}: expected pass, got ${report.violations}');
      } else if (expectedRule != null &&
          !report.violations.any(
            (SensitiveDataViolation violation) =>
                violation.rule == expectedRule,
          )) {
        failures.add(
          '${entry.key}: expected $expectedRule, got ${report.violations}',
        );
      }
    } finally {
      workspace.deleteSync(recursive: true);
    }
  }
  if (failures.isNotEmpty) {
    for (final String failure in failures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Sensitive data fixture check passed (${expectations.length} fixtures).',
  );
}

void _copyFixture(Directory source, Directory destination) {
  final String sourcePrefix = source.path.endsWith(Platform.pathSeparator)
      ? source.path
      : '${source.path}${Platform.pathSeparator}';
  for (final FileSystemEntity entity in source.listSync(recursive: true)) {
    if (entity is! File) continue;
    final String relative = entity.path.substring(sourcePrefix.length);
    final String outputRelative = relative.endsWith('.txt')
        ? relative.substring(0, relative.length - 4)
        : relative;
    final File output = File(
      destination.uri.resolve(outputRelative).toFilePath(),
    );
    output.parent.createSync(recursive: true);
    entity.copySync(output.path);
  }
}
