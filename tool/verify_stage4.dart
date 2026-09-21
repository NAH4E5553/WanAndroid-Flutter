import 'dart:io';

void main() {
  final failures = <String>[];
  for (final path in <String>[
    'lib/src/core/reader/reader_url_policy.dart',
    'lib/src/core/reader/reader_failure_classifier.dart',
    'lib/src/data/database/reading_history_database.dart',
    'lib/src/data/database/reading_history_database.g.dart',
    'lib/src/data/repository/contract/reading_history_repository.dart',
    'lib/src/data/repository/implementation/default_reading_history_repository.dart',
    'lib/src/features/reader/view/article_reader_screen.dart',
    'lib/src/features/profile/view/reading_history_screen.dart',
    'test/core/reader/reader_url_policy_test.dart',
    'test/core/reader/reader_failure_classifier_test.dart',
    'test/data/repository/reading_history_repository_test.dart',
    'test/features/profile/reading_history_screen_test.dart',
    'integration_test/reader_history_test.dart',
    'integration_test/stage4_ci_test.dart',
    'android/app/src/debug/res/xml/reader_test_network_security_config.xml',
    'third_party/webview_flutter_android/README.local-patch.md',
  ]) {
    if (!File(path).existsSync()) failures.add('Missing stage 4 file: $path');
  }
  const localPatchJava =
      'third_party/webview_flutter_android/android/src/main/java/'
      'io/flutter/plugins/webviewflutter/WebViewClientProxyApi.java';
  const localPatchController =
      'third_party/webview_flutter_android/lib/src/android_webview_controller.dart';
  const localPatchConstants =
      'third_party/webview_flutter_android/lib/src/android_webkit_constants.dart';
  if (File('lib/src/features/home/view/home_preview_screen.dart')
      .existsSync()) {
    failures.add('Stage 1 article placeholder remains in production');
  }
  for (final (path, content) in <(String, String)>[
    (localPatchJava, 'public boolean onRenderProcessGone('),
    (
      localPatchJava,
      'dev.flutter.local_patch.webview_flutter_android/WebViewClient.onRenderProcessGone',
    ),
    (localPatchConstants, 'errorWebContentProcessTerminated = -100'),
    (localPatchController, 'errorWebContentProcessTerminated'),
    (
      localPatchController,
      'dev.flutter.local_patch.webview_flutter_android/WebViewClient.onRenderProcessGone',
    ),
    ('pubspec.yaml', 'third_party/webview_flutter_android'),
    (
      'lib/src/features/reader/view/article_reader_screen.dart',
      'if (kind == ReaderFailureKind.renderer)',
    ),
    ('lib/src/app/router/app_routes.dart', 'buildArticleReaderScreen('),
    ('lib/src/app/router/app_routes.dart', 'HistoryReaderRouteData'),
    (
      'lib/src/app/bootstrap/bootstrap.dart',
      'DefaultReadingHistoryRepository(',
    ),
    (
      'lib/src/app/bootstrap/bootstrap.dart',
      'dependencies.collectionRepository',
    ),
    ('lib/src/core/ui/swipe_reveal_action_item.dart', 'onHorizontalDragEnd'),
    (
      'lib/src/features/profile/view/reading_history_screen.dart',
      'SwipeRevealActionItem(',
    ),
    (
      'lib/src/features/reader/view/article_reader_screen.dart',
      'WebViewWidget(',
    ),

    (
      'android/app/src/debug/AndroidManifest.xml',
      'reader_test_network_security_config',
    ),
  ]) {
    final file = File(path);
    if (!file.existsSync() || !file.readAsStringSync().contains(content)) {
      failures.add('$path does not contain: $content');
    }
  }
  for (final (path, content) in <(String, String)>[
    (
      'lib/src/app/bootstrap/bootstrap.dart',
      'dependencies.collectionRepository',
    ),
    ('lib/src/core/ui/swipe_reveal_action_item.dart', 'onHorizontalDragEnd'),
    (
      'lib/src/features/profile/view/reading_history_screen.dart',
      'SwipeRevealActionItem(',
    ),
  ]) {
    final File file = File(path);
    if (!file.existsSync() || !file.readAsStringSync().contains(content)) {
      failures.add('$path does not contain: $content');
    }
  }
  if (failures.isNotEmpty) {
    for (final failure in failures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('Stage 4 structural check passed.');
}
