import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  try {
    final _Options options = _Options.parse(arguments);
    if (options.showHelp) {
      stdout.writeln(_usage);
      return;
    }

    final Directory root = File.fromUri(Platform.script).parent.parent.absolute;
    final _Runner runner = _Runner(root: root, dryRun: options.dryRun);
    final String dart = Platform.resolvedExecutable;
    const String packageConfig = 'tool/standalone_package_config.json';

    await runner.run('Documentation consistency', 'python3', <String>[
      '.github/scripts/verify_docs.py',
    ]);

    if (!options.quick) {
      final _WorktreeSnapshot before = await _WorktreeSnapshot.capture(
        root,
        dryRun: options.dryRun,
      );
      await runner.run('Resolve Flutter dependencies', 'flutter', <String>[
        'pub',
        'get',
      ]);
      await runner.run('Generate Dart sources', dart, <String>[
        'run',
        'build_runner',
        'build',
      ]);
      await runner.run('Generate launcher icons', dart, <String>[
        '--packages=$packageConfig',
        'tool/generate_launcher_icons.dart',
      ]);
      final _WorktreeSnapshot after = await _WorktreeSnapshot.capture(
        root,
        dryRun: options.dryRun,
      );
      if (!options.dryRun && before != after) {
        throw StateError(
          'Generators changed tracked or untracked project files. '
          'Review and accept the generated changes, then run verification again.',
        );
      }
    }

    await runner.run('Dart formatting', dart, <String>[
      'format',
      '--output=none',
      '--set-exit-if-changed',
      '.',
    ]);
    await runner.run('Analysis Server diagnostics', dart, <String>[
      '--packages=$packageConfig',
      'tool/analyze_project.dart',
    ]);
    await runner.run('Architecture rules', dart, <String>[
      '--packages=$packageConfig',
      'tool/verify_architecture.dart',
    ]);
    await runner.run('Architecture rule fixtures', dart, <String>[
      '--packages=$packageConfig',
      'tool/verify_architecture_fixtures.dart',
    ]);
    await runner.run('Sensitive-data rules', dart, <String>[
      '--packages=$packageConfig',
      'tool/verify_sensitive_data.dart',
    ]);
    await runner.run('Sensitive-data rule fixtures', dart, <String>[
      '--packages=$packageConfig',
      'tool/verify_sensitive_data_fixtures.dart',
    ]);

    for (final File stageCheck in _stageChecks(root)) {
      await runner.run(
        'Stage ${_stageNumber(stageCheck.path)} structure',
        dart,
        <String>[
          '--packages=$packageConfig',
          _relativeToRoot(root, stageCheck),
        ],
      );
    }

    await runner.run('Flutter analyze', 'flutter', <String>[
      'analyze',
      '--no-pub',
    ]);
    await runner.run('Unit and widget tests', 'flutter', <String>[
      'test',
      if (!options.quick) '--coverage',
      '--no-pub',
    ]);

    final File integration = _latestIntegrationTest(root);
    if (options.android) {
      final String device = await _resolveDevice(
        platform: _DevicePlatform.android,
        explicitId: options.androidDevice,
        dryRun: options.dryRun,
      );
      await runner.run('Android integration', 'flutter', <String>[
        'test',
        _relativeToRoot(root, integration),
        '-d',
        device,
        '--no-pub',
        '--reporter',
        'expanded',
      ]);
      await runner.run('Android debug APK', 'flutter', <String>[
        'build',
        'apk',
        '--debug',
        '--no-pub',
      ]);
    }

    if (options.ios) {
      final String device = await _resolveDevice(
        platform: _DevicePlatform.iosSimulator,
        explicitId: options.iosDevice,
        dryRun: options.dryRun,
      );
      await runner.run('iOS integration', 'flutter', <String>[
        'test',
        _relativeToRoot(root, integration),
        '-d',
        device,
        '--no-pub',
        '--reporter',
        'expanded',
      ]);
      await runner.run('iOS simulator debug build', 'flutter', <String>[
        'build',
        'ios',
        '--simulator',
        '--debug',
        '--no-pub',
      ]);
    }

    stdout.writeln(
      options.dryRun
          ? 'Verification plan generated; no checks were executed.'
          : 'PR verification passed.',
    );
  } on Object catch (error) {
    stderr.writeln('PR verification failed: $error');
    stderr.writeln('Run with --help for usage.');
    exitCode = 1;
  }
}

List<File> _stageChecks(Directory root) {
  final List<File> checks =
      Directory('${root.path}${Platform.pathSeparator}tool')
          .listSync()
          .whereType<File>()
          .where((File file) {
            return RegExp(r'verify_stage\d+\.dart$').hasMatch(file.path);
          })
          .toList()
        ..sort((File left, File right) {
          return _stageNumber(left.path).compareTo(_stageNumber(right.path));
        });
  if (checks.isEmpty) {
    throw StateError('No tool/verify_stage<N>.dart checks were found.');
  }
  return checks;
}

int _stageNumber(String filePath) {
  final RegExpMatch? match = RegExp(r'verify_stage(\d+)\.dart$')
      .firstMatch(filePath);
  if (match == null) {
    throw StateError('Cannot determine stage number from $filePath.');
  }
  return int.parse(match.group(1)!);
}

File _latestIntegrationTest(Directory root) {
  final List<(int, File)> tests =
      Directory('${root.path}${Platform.pathSeparator}integration_test')
          .listSync()
          .whereType<File>()
          .map((File file) {
            final RegExpMatch? match = RegExp(r'stage(\d+)_ci_test\.dart$')
                .firstMatch(file.path);
            return match == null ? null : (int.parse(match.group(1)!), file);
          })
          .whereType<(int, File)>()
          .toList()
        ..sort(
          ((int, File) left, (int, File) right) => left.$1.compareTo(right.$1),
        );
  if (tests.isEmpty) {
    throw StateError('No integration_test/stage<N>_ci_test.dart was found.');
  }
  return tests.last.$2;
}

String _relativeToRoot(Directory root, File file) {
  final String prefix = '${root.path}${Platform.pathSeparator}';
  if (!file.path.startsWith(prefix)) {
    throw StateError('${file.path} is outside ${root.path}.');
  }
  return file.path.substring(prefix.length);
}

enum _DevicePlatform { android, iosSimulator }

Future<String> _resolveDevice({
  required _DevicePlatform platform,
  required String? explicitId,
  required bool dryRun,
}) async {
  if (explicitId != null) return explicitId;
  if (dryRun) {
    return platform == _DevicePlatform.android
        ? '<auto-android-device>'
        : '<auto-ios-simulator>';
  }

  final ProcessResult result = await Process.run('flutter', <String>[
    'devices',
    '--machine',
  ]);
  if (result.exitCode != 0) {
    throw StateError('flutter devices failed: ${result.stderr}');
  }
  final Object? decoded = jsonDecode(result.stdout as String);
  if (decoded is! List<Object?>) {
    throw StateError('flutter devices returned an unexpected payload.');
  }
  final List<Map<String, Object?>> matches = decoded
      .whereType<Map<String, Object?>>()
      .where((Map<String, Object?> device) {
        final String target = '${device['targetPlatform'] ?? ''}';
        if (platform == _DevicePlatform.android) {
          return target.startsWith('android');
        }
        return target == 'ios' && device['emulator'] == true;
      })
      .toList(growable: false);
  if (matches.length != 1) {
    final String option = platform == _DevicePlatform.android
        ? '--android-device=<id>'
        : '--ios-device=<id>';
    final String found = matches.isEmpty
        ? 'none'
        : matches
              .map((Map<String, Object?> item) {
                return '${item['id']} (${item['name']})';
              })
              .join(', ');
    throw StateError(
      'Expected exactly one matching device, found $found. Pass $option.',
    );
  }
  return '${matches.single['id']}';
}

final class _Options {
  const _Options({
    required this.quick,
    required this.dryRun,
    required this.android,
    required this.ios,
    required this.androidDevice,
    required this.iosDevice,
    required this.showHelp,
  });

  factory _Options.parse(List<String> arguments) {
    bool quick = false;
    bool dryRun = false;
    bool android = false;
    bool ios = false;
    bool showHelp = false;
    String? androidDevice;
    String? iosDevice;

    for (final String argument in arguments) {
      switch (argument) {
        case '--quick':
          quick = true;
        case '--dry-run':
          dryRun = true;
        case '--android':
          android = true;
        case '--ios':
          ios = true;
        case '--all':
          android = true;
          ios = true;
        case '--help' || '-h':
          showHelp = true;
        default:
          if (argument.startsWith('--android-device=')) {
            androidDevice = argument.substring('--android-device='.length);
            android = true;
          } else if (argument.startsWith('--ios-device=')) {
            iosDevice = argument.substring('--ios-device='.length);
            ios = true;
          } else {
            throw FormatException('Unknown option: $argument');
          }
      }
    }
    if (quick && (android || ios)) {
      throw const FormatException(
        '--quick cannot be combined with platform integration checks.',
      );
    }
    if (androidDevice != null && androidDevice.isEmpty) {
      throw const FormatException('--android-device requires a device ID.');
    }
    if (iosDevice != null && iosDevice.isEmpty) {
      throw const FormatException('--ios-device requires a device ID.');
    }
    return _Options(
      quick: quick,
      dryRun: dryRun,
      android: android,
      ios: ios,
      androidDevice: androidDevice,
      iosDevice: iosDevice,
      showHelp: showHelp,
    );
  }

  final bool quick;
  final bool dryRun;
  final bool android;
  final bool ios;
  final String? androidDevice;
  final String? iosDevice;
  final bool showHelp;
}

final class _Runner {
  const _Runner({required this.root, required this.dryRun});

  final Directory root;
  final bool dryRun;

  Future<void> run(
    String label,
    String executable,
    List<String> arguments,
  ) async {
    stdout.writeln('\n==> $label');
    stdout.writeln(_displayCommand(executable, arguments));
    if (dryRun) return;
    final Process process = await Process.start(
      executable,
      arguments,
      workingDirectory: root.path,
      mode: ProcessStartMode.inheritStdio,
    );
    final int result = await process.exitCode;
    if (result != 0) {
      throw ProcessException(executable, arguments, '$label failed', result);
    }
  }
}

String _displayCommand(String executable, List<String> arguments) {
  return <String>[
    executable,
    ...arguments.map((String argument) {
      if (!argument.contains(RegExp(r'''[\s"']'''))) return argument;
      return "'${argument.replaceAll("'", "'\\''")}'";
    }),
  ].join(' ');
}

final class _WorktreeSnapshot {
  const _WorktreeSnapshot({
    required this.status,
    required this.unstagedDiff,
    required this.stagedDiff,
  });

  factory _WorktreeSnapshot.empty() {
    return const _WorktreeSnapshot(
      status: '',
      unstagedDiff: '',
      stagedDiff: '',
    );
  }

  static Future<_WorktreeSnapshot> capture(
    Directory root, {
    required bool dryRun,
  }) async {
    if (dryRun) return _WorktreeSnapshot.empty();
    return _WorktreeSnapshot(
      status: await _git(root, <String>[
        'status',
        '--porcelain=v1',
        '-z',
        '--untracked-files=all',
      ]),
      unstagedDiff: await _git(root, <String>[
        'diff',
        '--binary',
        '--no-ext-diff',
      ]),
      stagedDiff: await _git(root, <String>[
        'diff',
        '--cached',
        '--binary',
        '--no-ext-diff',
      ]),
    );
  }

  final String status;
  final String unstagedDiff;
  final String stagedDiff;

  @override
  bool operator ==(Object other) {
    return other is _WorktreeSnapshot &&
        status == other.status &&
        unstagedDiff == other.unstagedDiff &&
        stagedDiff == other.stagedDiff;
  }

  @override
  int get hashCode => Object.hash(status, unstagedDiff, stagedDiff);
}

Future<String> _git(Directory root, List<String> arguments) async {
  final ProcessResult result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      arguments,
      '${result.stderr}',
      result.exitCode,
    );
  }
  return result.stdout as String;
}

const String _usage = '''
Usage: dart run tool/verify_pr.dart [options]

Runs the repository's deterministic PR checks from the repository root.

Options:
  --quick                 Skip dependency resolution, generators and coverage.
  --android               Add latest-stage Android integration and APK build.
  --ios                   Add latest-stage iOS Simulator integration and build.
  --all                   Add both Android and iOS platform checks.
  --android-device=<id>   Use a specific Android device.
  --ios-device=<id>       Use a specific iOS Simulator.
  --dry-run               Print the command plan without executing it.
  --help, -h              Show this help.

Without an explicit device ID, a platform option requires exactly one matching
connected device. Dry-run output is planning evidence only, not verification.
''';
