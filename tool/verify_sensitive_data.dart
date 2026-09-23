import 'dart:io';

void main(List<String> arguments) {
  final Directory root = Directory(
    arguments.isEmpty ? Directory.current.path : arguments.first,
  ).absolute;
  final SensitiveDataReport report = SensitiveDataVerifier(root).verify();
  if (report.violations.isEmpty) {
    stdout.writeln(
      'Sensitive data check passed (${report.filesChecked} text files).',
    );
    return;
  }
  stderr.writeln('Sensitive data check failed:');
  for (final SensitiveDataViolation violation in report.violations) {
    stderr.writeln(violation);
  }
  exitCode = 1;
}

class SensitiveDataVerifier {
  SensitiveDataVerifier(this.root);

  final Directory root;

  static final RegExp _phone = RegExp(r'(?<![0-9])1[3-9][0-9]{9}(?![0-9])');
  static final RegExp _consoleLog = RegExp(
    r'\b(?:print|debugPrint|developer\.log)\s*\(',
  );
  static final RegExp _numericLoginCookie = RegExp(
    r'loginUserName\s*=\s*1[3-9][0-9]{9}',
    caseSensitive: false,
  );

  // Project-owned synthetic identities. A new value requires deliberate
  // review here; arbitrary valid-looking phone numbers are rejected everywhere.
  static const Set<String> _syntheticPhones = <String>{
    '13800138000',
    '13900139000',
  };

  SensitiveDataReport verify() {
    final List<SensitiveDataViolation> violations = <SensitiveDataViolation>[];
    int filesChecked = 0;
    for (final File file in _textFiles()) {
      filesChecked += 1;
      final String relative = _relative(file);
      final List<String> lines = file.readAsLinesSync();
      for (int index = 0; index < lines.length; index += 1) {
        final String line = lines[index];
        for (final RegExpMatch match in _phone.allMatches(line)) {
          final String value = match.group(0)!;
          if (!_syntheticPhones.contains(value)) {
            violations.add(
              SensitiveDataViolation(
                rule: 'REAL_IDENTITY_LITERAL',
                path: relative,
                line: index + 1,
                detail:
                    'valid-looking phone literal is not an approved fixture',
              ),
            );
          }
        }
        if (_numericLoginCookie.hasMatch(line)) {
          violations.add(
            SensitiveDataViolation(
              rule: 'NUMERIC_LOGIN_COOKIE',
              path: relative,
              line: index + 1,
              detail: 'numeric login identity must not be stored in a cookie fixture',
            ),
          );
        }
        if (_isAuthenticationSurface(relative) && _consoleLog.hasMatch(line)) {
          violations.add(
            SensitiveDataViolation(
              rule: 'AUTH_CONSOLE_LOG',
              path: relative,
              line: index + 1,
              detail:
                  'authentication and session surfaces must not log directly',
            ),
          );
        }
      }
    }
    return SensitiveDataReport(
      filesChecked: filesChecked,
      violations: violations,
    );
  }

  Iterable<File> _textFiles() sync* {
    const Set<String> extensions = <String>{
      '.dart',
      '.java',
      '.json',
      '.kt',
      '.kts',
      '.md',
      '.properties',
      '.swift',
      '.xml',
      '.yaml',
      '.yml',
    };
    final List<FileSystemEntity> entities =
        root.listSync(recursive: true, followLinks: false)..sort(
          (FileSystemEntity left, FileSystemEntity right) =>
              left.path.compareTo(right.path),
        );
    for (final FileSystemEntity entity in entities) {
      if (entity is! File) continue;
      final String relative = _relative(entity);
      if (_isExcluded(relative)) continue;
      final int dot = relative.lastIndexOf('.');
      if (dot < 0 || !extensions.contains(relative.substring(dot))) continue;
      yield entity;
    }
  }

  bool _isExcluded(String relative) {
    const List<String> excludedPrefixes = <String>[
      '.dart_tool/',
      '.git/',
      '.idea/',
      'android/.gradle/',
      'build/',
      'coverage/',
      'ios/Pods/',
      'stage0/prototypes/.dart_tool/',
      'stage0/prototypes/build/',
      'third_party/',
      'tool/test_fixtures/',
    ];
    return excludedPrefixes.any(relative.startsWith);
  }

  bool _isAuthenticationSurface(String relative) =>
      relative.startsWith('lib/src/data/network/session/') ||
      relative == 'lib/src/data/network/auth_network_data_source.dart' ||
      relative ==
          'lib/src/data/repository/implementation/default_auth_repository.dart' ||
      relative == 'integration_test/real_login_debug_test.dart';

  String _relative(FileSystemEntity entity) {
    final String prefix = root.path.endsWith(Platform.pathSeparator)
        ? root.path
        : '${root.path}${Platform.pathSeparator}';
    return entity.absolute.path.substring(prefix.length).replaceAll('\\', '/');
  }
}

class SensitiveDataReport {
  const SensitiveDataReport({
    required this.filesChecked,
    required this.violations,
  });

  final int filesChecked;
  final List<SensitiveDataViolation> violations;
}

class SensitiveDataViolation {
  const SensitiveDataViolation({
    required this.rule,
    required this.path,
    required this.line,
    required this.detail,
  });

  final String rule;
  final String path;
  final int line;
  final String detail;

  @override
  String toString() => '[$rule] $path:$line: $detail';
}
