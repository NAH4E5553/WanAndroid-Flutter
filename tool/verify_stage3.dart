import 'dart:io';

void main() {
  final List<String> failures = <String>[];
  for (final String path in <String>[
    'lib/src/model/topic.dart',
    'lib/src/data/repository/contract/topic_repository.dart',
    'lib/src/data/repository/implementation/default_topic_repository.dart',
    'lib/src/features/topics/state/topics_ui_state.dart',
    'lib/src/features/topics/view_model/topics_view_model.dart',
    'lib/src/features/topics/view/topics_screen.dart',
    'test/data/repository/default_topic_repository_test.dart',
    'test/features/topics/topics_view_model_test.dart',
    'test/features/topics/topics_screen_test.dart',
    'integration_test/topics_gestures_test.dart',
    'integration_test/stage3_ci_test.dart',
  ]) {
    if (!File(path).existsSync()) failures.add('Missing stage 3 file: $path');
  }
  if (File('lib/src/features/topics/view/topics_placeholder_screen.dart')
      .existsSync()) {
    failures.add('Stage 1 topics placeholder remains in production');
  }
  for (final (String path, String content) in <(String, String)>[
    (
      'lib/src/data/network/service/wan_api_service.dart',
      "_get('tree/json', cancellation)",
    ),
    (
      'lib/src/data/network/service/wan_api_service.dart',
      r"'article/list/$page/json'",
    ),
    ('lib/src/app/bootstrap/bootstrap.dart', 'DefaultTopicRepository(network)'),
    ('lib/src/features/topics/view/topics_screen.dart', 'PageView.builder('),
    (
      'lib/src/features/topics/view_model/topics_view_model.dart',
      'maxCachedCategories = 8',
    ),
  ]) {
    final File file = File(path);
    if (!file.existsSync() || !file.readAsStringSync().contains(content)) {
      failures.add('$path does not contain: $content');
    }
  }
  if (failures.isNotEmpty) {
    for (final String failure in failures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('Stage 3 structural check passed.');
}
