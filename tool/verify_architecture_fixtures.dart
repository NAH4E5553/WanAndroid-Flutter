import 'dart:io';

import 'verify_architecture.dart';

void main() {
  final Map<String, String?> expectations = <String, String?>{
    'direct_violation': 'FEATURE_DATA_IMPLEMENTATION',
    'relative_violation': 'FEATURE_DATA_IMPLEMENTATION',
    'barrel_violation': 'FEATURE_DATA_IMPLEMENTATION',
    'composition_root_pass': null,
  };
  final List<String> failures = <String>[];
  for (final MapEntry<String, String?> entry in expectations.entries) {
    final Directory fixture = Directory(
      Directory.current.uri
          .resolve('tool/test_fixtures/${entry.key}/')
          .toFilePath(),
    );
    final Directory workspace = Directory.systemTemp.createTempSync(
      'wanandroid_architecture_',
    );
    try {
      _copyFixture(fixture, workspace);
      final ArchitectureReport report = ArchitectureVerifier(workspace.path)
          .verify();
      final String? expectedRule = entry.value;
      if (expectedRule == null && report.violations.isNotEmpty) {
        failures.add('${entry.key}: expected pass, got ${report.violations}');
      } else if (expectedRule != null &&
          !report.violations.any(
            (ArchitectureViolation violation) => violation.rule == expectedRule,
          )) {
        failures.add(
          '${entry.key}: expected $expectedRule, checked '
          '${report.filesChecked} files, got ${report.violations}',
        );
      } else if (entry.key == 'barrel_violation' &&
          !report.violations.any(
            (ArchitectureViolation violation) => violation.indirect,
          )) {
        failures.add('${entry.key}: expected an indirect export violation');
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
  stdout.writeln('Architecture fixture check passed (4 fixtures).');
}

void _copyFixture(Directory source, Directory destination) {
  final String sourcePrefix = source.path.endsWith(Platform.pathSeparator)
      ? source.path
      : '${source.path}${Platform.pathSeparator}';
  for (final FileSystemEntity entity in source.listSync(recursive: true)) {
    if (entity is! File) {
      continue;
    }
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
