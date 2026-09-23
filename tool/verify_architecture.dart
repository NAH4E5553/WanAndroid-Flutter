import 'dart:io';

void main(List<String> arguments) {
  final String root = arguments.isEmpty
      ? Directory.current.path
      : arguments.first;
  final ArchitectureReport report = ArchitectureVerifier(root).verify();
  if (report.violations.isEmpty) {
    stdout.writeln(
      'Architecture check passed (${report.filesChecked} Dart files).',
    );
    return;
  }
  stderr.writeln('Architecture check failed:');
  for (final ArchitectureViolation violation in report.violations) {
    stderr.writeln(violation);
  }
  exitCode = 1;
}

class ArchitectureVerifier {
  ArchitectureVerifier(String root)
    : root = _normalize(Directory(root).absolute.path),
      sourceRoot = _normalize(
        Directory(root).absolute.uri.resolve('lib/src/').toFilePath(),
      );

  final String root;
  final String sourceRoot;

  ArchitectureReport verify() {
    final Directory directory = Directory(sourceRoot);
    if (!directory.existsSync()) {
      return const ArchitectureReport(
        filesChecked: 0,
        violations: <ArchitectureViolation>[],
      );
    }
    final List<File> files =
        directory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((File file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((File left, File right) => left.path.compareTo(right.path));
    final Map<String, List<_Directive>> graph = <String, List<_Directive>>{};
    for (final File file in files) {
      graph[_normalize(file.absolute.path)] = _parse(file);
    }

    final List<ArchitectureViolation> violations = <ArchitectureViolation>[];
    for (final File file in files) {
      final String source = _normalize(file.absolute.path);
      for (final _Directive directive in graph[source]!) {
        final String? target = _resolve(source, directive.uri);
        if (target == null || !_isWithin(sourceRoot, target)) {
          continue;
        }
        final String? rule = _forbiddenRule(source, target);
        if (rule != null) {
          violations.add(
            ArchitectureViolation(
              rule: rule,
              source: _relative(source),
              target: _relative(target),
              indirect: false,
            ),
          );
        }
        for (final String exported in _reachableExports(
          target,
          graph,
          <String>{},
        )) {
          final String? indirectRule = _forbiddenRule(source, exported);
          if (indirectRule != null) {
            violations.add(
              ArchitectureViolation(
                rule: indirectRule,
                source: _relative(source),
                target: _relative(exported),
                indirect: true,
              ),
            );
          }
        }
      }
    }
    final Map<String, ArchitectureViolation> unique =
        <String, ArchitectureViolation>{
          for (final ArchitectureViolation violation in violations)
            violation.toString(): violation,
        };
    return ArchitectureReport(
      filesChecked: files.length,
      violations: unique.values.toList(growable: false),
    );
  }

  List<_Directive> _parse(File file) {
    final RegExp pattern = RegExp(
      r'''^\s*(import|export|part)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    );
    return pattern
        .allMatches(file.readAsStringSync())
        .map((_DirectiveMatch match) => match.directive)
        .toList(growable: false);
  }

  String? _resolve(String source, String uri) {
    if (uri.startsWith('dart:')) {
      return null;
    }
    if (uri.startsWith('package:wanandroid_flutter/')) {
      final String suffix = uri.substring('package:wanandroid_flutter/'.length);
      return _normalize(
        Directory(root).uri.resolve('lib/$suffix').toFilePath(),
      );
    }
    if (uri.startsWith('package:')) {
      return null;
    }
    return _normalize(File(source).parent.uri.resolve(uri).toFilePath());
  }

  Set<String> _reachableExports(
    String target,
    Map<String, List<_Directive>> graph,
    Set<String> visited,
  ) {
    if (!visited.add(target)) {
      return const <String>{};
    }
    final Set<String> result = <String>{};
    for (final _Directive directive in graph[target] ?? const <_Directive>[]) {
      if (directive.kind != 'export') {
        continue;
      }
      final String? exported = _resolve(target, directive.uri);
      if (exported == null || !_isWithin(sourceRoot, exported)) {
        continue;
      }
      result.add(exported);
      result.addAll(_reachableExports(exported, graph, visited));
    }
    return result;
  }

  String? _forbiddenRule(String source, String target) {
    final List<String> from = _segments(_relative(source));
    final List<String> to = _segments(_relative(target));
    if (from.length < 2 || to.length < 2) {
      return null;
    }
    final bool targetDataImplementation = _startsWith(to, <String>[
      'data',
      'repository',
      'implementation',
    ]);
    final bool targetDataBoundary =
        targetDataImplementation ||
        _startsWith(to, <String>['data', 'network']) ||
        _startsWith(to, <String>['data', 'database']) ||
        _startsWith(to, <String>['data', 'storage']);

    if (from.first == 'features') {
      final String feature = from.length > 1 ? from[1] : '';
      final String area = from.length > 2 ? from[2] : '';
      final String sourceRelative = _relative(source);
      final String targetRelative = _relative(target);
      if (to.first == 'features' && to.length > 1 && to[1] != feature) {
        return 'FEATURE_CROSS_IMPLEMENTATION';
      }
      if (area == 'view' &&
          targetRelative == 'core/providers.dart' &&
          !_isTemporaryArchitectureDebt(sourceRelative, targetRelative)) {
        return 'VIEW_PROVIDER_COMPOSITION';
      }
      if (<String>{
            'view',
            'view_model',
            'component',
            'state',
            'policy',
          }.contains(area) &&
          targetDataBoundary) {
        return 'FEATURE_DATA_IMPLEMENTATION';
      }
      if (<String>{'view', 'component', 'state', 'policy'}.contains(area) &&
          to.first == 'data' &&
          !_isTemporaryArchitectureDebt(sourceRelative, targetRelative)) {
        return 'FEATURE_PRESENTATION_DATA';
      }
      if (area == 'view_model' && to.first == 'core' && to[1] == 'ui') {
        return 'VIEW_MODEL_UI';
      }
      if (area == 'component' &&
          to.first == 'features' &&
          to.length > 2 &&
          to[2] == 'view_model') {
        return 'COMPONENT_VIEW_MODEL';
      }
    }
    if (from.first == 'core' && <String>{'ui', 'theme'}.contains(from[1])) {
      if (to.first == 'data' || to.first == 'features') {
        return 'CORE_UI_BUSINESS';
      }
    }
    if (from.first == 'model' && to.first != 'model') {
      return 'MODEL_DEPENDENCY';
    }
    if (_startsWith(from, <String>['app', 'router']) &&
        to.first == 'features') {
      if (to.length < 3 || to[2] != 'navigation') {
        return 'ROUTER_FEATURE_PRIVATE';
      }
    }
    if (_startsWith(from, <String>['data', 'repository', 'contract']) &&
        (to.first == 'features' || targetDataBoundary)) {
      return 'REPOSITORY_CONTRACT_IMPLEMENTATION';
    }
    return null;
  }

  bool _isTemporaryArchitectureDebt(String source, String target) {
    // These exact dependencies predate the stricter presentation whitelist.
    // They remain visible instead of weakening the rule for an entire folder.
    // Remove each entry when the corresponding profile screen is moved behind
    // a ViewModel; no new source/target pair may be added as routine work.
    const Set<String> allowed = <String>{
      'features/profile/view/collections_screen.dart->core/providers.dart',
      'features/profile/view/collections_screen.dart->data/repository/contract/collection_repository.dart',
      'features/profile/view/profile_screen.dart->core/providers.dart',
      'features/profile/view/profile_screen.dart->data/repository/contract/auth_repository.dart',
      'features/profile/view/theme_settings_screen.dart->core/providers.dart',
    };
    return allowed.contains('$source->$target');
  }

  bool _startsWith(List<String> value, List<String> prefix) {
    if (value.length < prefix.length) {
      return false;
    }
    for (int index = 0; index < prefix.length; index += 1) {
      if (value[index] != prefix[index]) {
        return false;
      }
    }
    return true;
  }

  String _relative(String file) => file.substring(sourceRoot.length + 1);
}

String _normalize(String value) {
  String normalized = Uri.file(File(value).absolute.path)
      .normalizePath()
      .toFilePath();
  if (normalized.endsWith(Platform.pathSeparator) &&
      Directory(normalized).parent.path != normalized) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool _isWithin(String parent, String child) =>
    child.startsWith('$parent${Platform.pathSeparator}');

List<String> _segments(String value) => value
    .split(Platform.pathSeparator)
    .where((String part) => part.isNotEmpty)
    .toList();

class ArchitectureReport {
  const ArchitectureReport({
    required this.filesChecked,
    required this.violations,
  });

  final int filesChecked;
  final List<ArchitectureViolation> violations;
}

class ArchitectureViolation {
  const ArchitectureViolation({
    required this.rule,
    required this.source,
    required this.target,
    required this.indirect,
  });

  final String rule;
  final String source;
  final String target;
  final bool indirect;

  @override
  String toString() =>
      '[$rule] $source -> $target${indirect ? ' (via export)' : ''}';
}

class _Directive {
  const _Directive(this.kind, this.uri);

  final String kind;
  final String uri;
}

extension on RegExpMatch {
  _Directive get directive => _Directive(group(1)!, group(2)!);
}

typedef _DirectiveMatch = RegExpMatch;
