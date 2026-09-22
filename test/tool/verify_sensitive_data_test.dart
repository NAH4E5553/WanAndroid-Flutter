import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/verify_sensitive_data.dart';

void main() {
  final Map<String, String?> expectations = <String, String?>{
    'sensitive_data_pass': null,
    'sensitive_data_phone_violation': 'REAL_IDENTITY_LITERAL',
    'sensitive_data_cookie_violation': 'NUMERIC_LOGIN_COOKIE',
    'sensitive_data_log_violation': 'AUTH_CONSOLE_LOG',
  };

  for (final MapEntry<String, String?> entry in expectations.entries) {
    test('${entry.key} reports ${entry.value ?? 'no violation'}', () async {
      final Directory fixture = await _copyFixture(entry.key);
      addTearDown(() => fixture.delete(recursive: true));
      final SensitiveDataReport report = SensitiveDataVerifier(fixture)
          .verify();
      if (entry.value case final String rule) {
        expect(
          report.violations.any(
            (SensitiveDataViolation violation) => violation.rule == rule,
          ),
          isTrue,
        );
      } else {
        expect(report.violations, isEmpty);
      }
    });
  }
}

Future<Directory> _copyFixture(String name) async {
  final Directory source = Directory(p.join('tool', 'test_fixtures', name));
  final Directory destination = await Directory.systemTemp.createTemp(
    'wanandroid_sensitive_data_',
  );
  await for (final FileSystemEntity entity in source.list(recursive: true)) {
    if (entity is! File) continue;
    final String relative = p.relative(entity.path, from: source.path);
    final String outputRelative = relative.endsWith('.txt')
        ? relative.substring(0, relative.length - 4)
        : relative;
    final File output = File(p.join(destination.path, outputRelative));
    await output.parent.create(recursive: true);
    await entity.copy(output.path);
  }
  return destination;
}
