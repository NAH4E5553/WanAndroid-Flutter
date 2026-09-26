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
    'lib/src/features/auth/policy/phone_number_policy.dart',
    'lib/src/features/auth/state/login_ui_state.dart',
    'lib/src/features/auth/navigation/auth_navigation.dart',
    'lib/src/features/auth/view/login_screen.dart',
    'lib/src/features/auth/view_model/login_view_model.dart',
    'lib/src/features/profile/view/profile_screen.dart',
    'lib/src/features/profile/view/theme_settings_screen.dart',
    'lib/src/features/profile/view/collections_screen.dart',
    'lib/src/features/profile/view_model/profile_view_model.dart',
    'lib/src/features/profile/view_model/theme_settings_view_model.dart',
    'lib/src/features/profile/view_model/collections_view_model.dart',
    'lib/src/features/reader/view_model/reader_collection_view_model.dart',
    'lib/src/core/ui/swipe_reveal_action_item.dart',
    'test/data/session/session_stage5_test.dart',
    'test/data/session/session_interceptor_stage5_test.dart',
    'test/data/network/article_network_data_source_session_test.dart',
    'test/data/repository/collection_repository_stage5_test.dart',
    'test/features/auth/login_screen_test.dart',
    'test/features/auth/login_view_model_test.dart',
    'test/features/profile/profile_view_model_test.dart',
    'test/features/profile/collections_view_model_test.dart',
    'test/features/reader/reader_collection_view_model_test.dart',
    'test/core/theme/theme_controller_test.dart',
    'test/data/storage/theme_preferences_test.dart',
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
    (
      'lib/src/app/bootstrap/bootstrap.dart',
      'readerCollectionViewModelProvider.overrideWithValue',
    ),
    (
      'lib/src/app/bootstrap/app_dependencies.dart',
      'DefaultArticleNetworkDataSource(\n    service,\n    sessionStore,',
    ),
    (
      'lib/src/features/auth/navigation/auth_navigation.dart',
      'viewModel.cancel()',
    ),
    (
      'lib/src/data/network/session/session_interceptor.dart',
      'flushResponseCookies',
    ),
    (
      'test/data/session/session_interceptor_stage5_test.dart',
      'SESSION-01 delayed old response cannot expire or rotate a newer session',
    ),
    (
      'test/features/auth/login_view_model_test.dart',
      'UI-07 leaving cancels login and ignores a late success',
    ),
    ('lib/src/data/storage/theme_preferences.dart', 'theme.selection.v1'),
    (
      'lib/src/features/profile/view/theme_settings_screen.dart',
      '无法读取已保存主题，当前使用默认设置',
    ),
    (
      'lib/src/features/profile/view/profile_screen.dart',
      'profileViewModelProvider',
    ),
    (
      'lib/src/features/profile/view/collections_screen.dart',
      'collectionsViewModelProvider',
    ),
    (
      'lib/src/features/profile/view/theme_settings_screen.dart',
      'themeSettingsViewModelProvider',
    ),
    (
      'test/core/theme/theme_controller_test.dart',
      'rapid selections serialize writes and persist the latest',
    ),
    (
      'test/data/storage/theme_preferences_test.dart',
      'all theme selections round-trip through stable storage values',
    ),
    (
      'integration_test/stage5_ci_test.dart',
      'stage 5 UI-07: theme, guest gates and controlled login',
    ),
    (
      'integration_test/stage5_ci_test.dart',
      'stage 5 UI-07: leaving login cancels the in-flight request',
    ),
  ]) {
    final File file = File(path);
    if (!file.existsSync() || !file.readAsStringSync().contains(content)) {
      failures.add('$path does not contain: $content');
    }
  }
  final String loginView = File('lib/src/features/auth/view/login_screen.dart')
      .readAsStringSync();
  for (final String forbidden in <String>[
    'authRepositoryProvider',
    'flutter_riverpod',
    'labelText:',
  ]) {
    if (loginView.contains(forbidden)) {
      failures.add('login_screen.dart contains forbidden coupling: $forbidden');
    }
  }
  for (final String path in <String>[
    'integration_test/real_login_debug_test.dart',
    'lib/src/data/mapper/wan_response_mapper.dart',
    'lib/src/data/repository/implementation/default_auth_repository.dart',
  ]) {
    if (File(path).readAsStringSync().contains('print(')) {
      failures.add('$path must not print account or server response data');
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
