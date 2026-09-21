import 'dart:io';

void main() {
  final failures = <String>[];
  for (final path in <String>[
    'lib/src/model/user.dart',
    'lib/src/model/collection.dart',
    'lib/src/data/network/session/session_models.dart',
    'lib/src/data/network/session/web_cookie.dart',
    'lib/src/data/network/session/session_store.dart',
    'lib/src/data/network/session/session_interceptor.dart',
    'lib/src/data/network/session/session_commit_coordinator.dart',
    'lib/src/data/storage/session_storage.dart',
    'lib/src/data/storage/secure_session_storage.dart',
    'lib/src/data/storage/theme_preferences.dart',
    'lib/src/data/repository/contract/auth_repository.dart',
    'lib/src/data/repository/contract/collection_repository.dart',
    'lib/src/data/repository/implementation/default_auth_repository.dart',
    'lib/src/data/repository/implementation/default_collection_repository.dart',
    'lib/src/features/auth/view/login_screen.dart',
    'lib/src/features/profile/view/profile_screen.dart',
    'lib/src/features/profile/view/theme_settings_screen.dart',
    'lib/src/features/profile/view/collections_screen.dart',
    'lib/src/core/ui/swipe_reveal_action_item.dart',
    'test/data/session/session_stage5_test.dart',
    'test/data/repository/collection_repository_stage5_test.dart',
    'test/features/profile/theme_settings_stage5_test.dart',
    'integration_test/stage5_ci_test.dart',
  ]) {
    if (!File(path).existsSync()) failures.add('Missing stage 5 file: $path');
  }
  for (final (path, content) in <(String, String)>[
    (
      'lib/src/data/network/session/session_store.dart',
      'authenticatedVersionKey',
    ),
    (
      'lib/src/data/repository/implementation/default_collection_repository.dart',
      '_reconcileLocked',
    ),
    ('lib/src/app/router/app_routes.dart', "path: '/login'"),
    (
      'lib/src/features/reader/view/article_reader_screen.dart',
      '_toggleCollect',
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
  stdout.writeln('Stage 5 structural check passed.');
}
