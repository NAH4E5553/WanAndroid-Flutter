import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/verify_architecture.dart';

void main() {
  test('direct package import violation fails', () async {
    final ArchitectureReport report = await _verifyFixture('direct_violation');
    expect(report.violations, isNotEmpty);
    expect(report.violations.first.rule, 'FEATURE_DATA_IMPLEMENTATION');
  });

  test('relative import violation fails', () async {
    final ArchitectureReport report = await _verifyFixture(
      'relative_violation',
    );
    expect(report.violations, isNotEmpty);
    expect(report.violations.first.rule, 'FEATURE_DATA_IMPLEMENTATION');
  });

  test('barrel export cannot hide a forbidden dependency', () async {
    final ArchitectureReport report = await _verifyFixture('barrel_violation');
    expect(
      report.violations.any((ArchitectureViolation item) => item.indirect),
      isTrue,
    );
  });

  test('composition root may bind contract to implementation', () async {
    final ArchitectureReport report = await _verifyFixture(
      'composition_root_pass',
    );
    expect(report.violations, isEmpty);
  });
}

Future<ArchitectureReport> _verifyFixture(String name) async {
  final Directory source = Directory(p.join('tool', 'test_fixtures', name));
  final Directory destination = await Directory.systemTemp.createTemp(
    'wanandroid_architecture_',
  );
  addTearDown(() => destination.delete(recursive: true));
  await for (final FileSystemEntity entity in source.list(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    final String relative = p.relative(entity.path, from: source.path);
    final String outputRelative = relative.endsWith('.txt')
        ? relative.substring(0, relative.length - 4)
        : relative;
    final File output = File(p.join(destination.path, outputRelative));
    await output.parent.create(recursive: true);
    await entity.copy(output.path);
  }
  return ArchitectureVerifier(destination.path).verify();
}
