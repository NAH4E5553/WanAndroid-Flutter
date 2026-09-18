import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final String root = Directory.current.absolute.path;
  final Directory sdk = File(Platform.resolvedExecutable).parent.parent;
  final File serverSnapshot = File(
    sdk.uri.resolve('bin/snapshots/analysis_server.dart.snapshot').toFilePath(),
  );
  final Directory cache = Directory.systemTemp.createTempSync(
    'wanandroid_analysis_',
  );
  final Map<String, List<_Diagnostic>> diagnostics =
      <String, List<_Diagnostic>>{};
  final Completer<void> completed = Completer<void>();
  bool rootsAccepted = false;
  late final Process process;
  Timer? timeout;

  try {
    process = await Process.start(Platform.resolvedExecutable, <String>[
      serverSnapshot.path,
      '--dart-sdk=${sdk.path}',
      '--cache=${cache.path}',
      '--packages=$root/.dart_tool/package_config.json',
    ]);
    process.stderr.transform(utf8.decoder).listen(stderr.write);
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
          final Object? decoded = jsonDecode(line);
          if (decoded is! Map<String, Object?>) {
            return;
          }
          if (decoded['id'] == 'set-roots') {
            rootsAccepted = true;
          }
          if (decoded['id'] == 'set-subscriptions') {
            process.stdin.writeln(
              jsonEncode(<String, Object>{
                'id': 'set-roots',
                'method': 'analysis.setAnalysisRoots',
                'params': <String, Object>{
                  'included': <String>[root],
                  'excluded': <String>[
                    '$root/.dart_tool',
                    '$root/build',
                    '$root/stage0',
                    '$root/tool/test_fixtures',
                    '$root/android',
                    '$root/ios',
                  ],
                },
              }),
            );
          }
          if (decoded['error'] != null && !completed.isCompleted) {
            completed.completeError(
              StateError('Analysis protocol error: ${decoded['error']}'),
            );
          }
          if (decoded['event'] == 'analysis.errors') {
            final Map<String, Object?> params =
                decoded['params']! as Map<String, Object?>;
            final String file = params['file']! as String;
            final List<Object?> rawErrors = params['errors']! as List<Object?>;
            diagnostics[file] = rawErrors
                .cast<Map<String, Object?>>()
                .map(_Diagnostic.fromJson)
                .toList(growable: false);
          }
          if (decoded['event'] == 'server.status') {
            final Map<String, Object?> params =
                decoded['params']! as Map<String, Object?>;
            final Object? rawAnalysis = params['analysis'];
            if (rawAnalysis is Map<String, Object?>) {
              final bool analyzing = rawAnalysis['isAnalyzing']! as bool;
              if (rootsAccepted && !analyzing) {
                process.stdin.writeln(
                  jsonEncode(<String, Object>{
                    'id': 'shutdown',
                    'method': 'server.shutdown',
                  }),
                );
                unawaited(process.stdin.close());
                if (!completed.isCompleted) {
                  completed.complete();
                }
              }
            }
          }
          if (decoded['event'] == 'server.error') {
            final Map<String, Object?> params =
                decoded['params']! as Map<String, Object?>;
            stderr.writeln('Analysis server error: ${params['message']}');
            if (!completed.isCompleted) {
              completed.completeError(StateError('${params['message']}'));
            }
          }
        });

    process.stdin.writeln(
      jsonEncode(<String, Object>{
        'id': 'set-subscriptions',
        'method': 'server.setSubscriptions',
        'params': <String, Object>{
          'subscriptions': <String>['STATUS'],
        },
      }),
    );
    timeout = Timer(const Duration(seconds: 90), () {
      if (!completed.isCompleted) {
        completed.completeError(
          TimeoutException('Analysis did not finish within 90 seconds.'),
        );
      }
    });
    await completed.future;
    await process.exitCode;
  } finally {
    timeout?.cancel();
    if (cache.existsSync()) {
      cache.deleteSync(recursive: true);
    }
  }

  final List<MapEntry<String, _Diagnostic>> issues =
      diagnostics.entries
          .expand(
            (MapEntry<String, List<_Diagnostic>> entry) => entry.value.map(
              (_Diagnostic issue) =>
                  MapEntry<String, _Diagnostic>(entry.key, issue),
            ),
          )
          .toList()
        ..sort((
          MapEntry<String, _Diagnostic> left,
          MapEntry<String, _Diagnostic> right,
        ) {
          final int fileOrder = left.key.compareTo(right.key);
          return fileOrder == 0
              ? left.value.offset.compareTo(right.value.offset)
              : fileOrder;
        });
  if (issues.isEmpty) {
    stdout.writeln('Analysis server check passed (no diagnostics).');
    return;
  }
  for (final MapEntry<String, _Diagnostic> issue in issues) {
    stdout.writeln('${issue.key}:${issue.value}');
  }
  exitCode = 1;
}

class _Diagnostic {
  const _Diagnostic({
    required this.severity,
    required this.type,
    required this.message,
    required this.offset,
    required this.line,
    required this.column,
  });

  factory _Diagnostic.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> location =
        json['location']! as Map<String, Object?>;
    final Map<String, Object?> start = location['startLine'] == null
        ? <String, Object?>{}
        : location;
    return _Diagnostic(
      severity: json['severity']! as String,
      type: json['type']! as String,
      message: json['message']! as String,
      offset: location['offset']! as int,
      line: start['startLine']! as int,
      column: start['startColumn']! as int,
    );
  }

  final String severity;
  final String type;
  final String message;
  final int offset;
  final int line;
  final int column;

  @override
  String toString() => '$line:$column · $severity · $type · $message';
}
