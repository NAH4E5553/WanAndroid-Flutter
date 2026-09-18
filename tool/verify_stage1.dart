import 'dart:convert';
import 'dart:io';

void main() {
  final Directory root = Directory.current;
  final List<String> required = <String>[
    'pubspec.yaml',
    'pubspec.lock',
    'android/app/src/main/AndroidManifest.xml',
    'ios/Runner/Info.plist',
    'lib/src/app/app.dart',
    'lib/src/app/router/app_router.dart',
    'lib/src/app/router/app_routes.g.dart',
    'lib/src/core/theme/wan_theme.dart',
    'lib/src/core/ui/app_scaffold.dart',
    'lib/src/core/ui/app_top_bar.dart',
    'lib/src/core/ui/article_card.dart',
    'lib/src/features/home/view/home_screen.dart',
    'test/core/navigation/branch_stack_snapshot_test.dart',
    'integration_test/navigation_restoration_test.dart',
    'tool/analyze_project.dart',
    'tool/generate_launcher_icons.dart',
    'tool/verify_architecture.dart',
    'tool/verify_architecture_fixtures.dart',
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
  ];
  final List<String> missing = required
      .where((String path) => !File('${root.path}/$path').existsSync())
      .toList(growable: false);
  final List<String> failures = <String>[];
  if (missing.isNotEmpty) {
    failures.add('Missing stage 1 files: ${missing.join(', ')}');
  }
  if (!File('${root.path}/.github/workflows/stage1.yml').existsSync() &&
      !File('${root.path}/.github/workflows/stage2.yml').existsSync()) {
    failures.add('Missing active quality workflow.');
  }
  final File frozenLock = File(
    '${root.path}/stage0/dependency_lock/pubspec.lock',
  );
  final File productionLock = File('${root.path}/pubspec.lock');
  if (frozenLock.existsSync() && productionLock.existsSync()) {
    if (base64Encode(frozenLock.readAsBytesSync()) !=
        base64Encode(productionLock.readAsBytesSync())) {
      failures.add('pubspec.lock differs from the frozen stage 0 lock.');
    }
  }
  _expectContains(
    failures,
    File('${root.path}/android/app/build.gradle.kts'),
    'applicationId = "com.personal.wanandroid.flutter"',
  );
  _expectContains(
    failures,
    File('${root.path}/android/app/build.gradle.kts'),
    'minSdk = 24',
  );
  _expectContains(
    failures,
    File('${root.path}/android/app/src/main/AndroidManifest.xml'),
    'android:label="WanAndroid Flutter"',
  );
  _expectContains(
    failures,
    File('${root.path}/android/app/src/main/AndroidManifest.xml'),
    'android:allowBackup="false"',
  );
  _expectContains(
    failures,
    File('${root.path}/android/app/src/main/AndroidManifest.xml'),
    'android:usesCleartextTraffic="false"',
  );
  _expectContains(
    failures,
    File('${root.path}/ios/Runner.xcodeproj/project.pbxproj'),
    'PRODUCT_BUNDLE_IDENTIFIER = com.personal.wanandroid.flutter;',
  );
  _expectContains(
    failures,
    File('${root.path}/ios/Runner.xcodeproj/project.pbxproj'),
    'IPHONEOS_DEPLOYMENT_TARGET = 15.0;',
  );
  _expectContains(
    failures,
    File('${root.path}/ios/Runner/Info.plist'),
    '<string>WanAndroid Flutter</string>',
  );
  if (failures.isNotEmpty) {
    for (final String failure in failures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('Stage 1 structural check passed.');
}

void _expectContains(List<String> failures, File file, String expected) {
  if (!file.existsSync() || !file.readAsStringSync().contains(expected)) {
    failures.add('${file.path} does not contain: $expected');
  }
}
