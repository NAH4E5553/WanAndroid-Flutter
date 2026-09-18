import 'dart:io';

void main() {
  final Directory root = Directory.current;
  final List<String> required = <String>[
    'lib/src/core/cancellation/request_cancellation.dart',
    'lib/src/core/paging/paging_controller.dart',
    'lib/src/core/paging/paging_state.dart',
    'lib/src/core/platform/app_visibility.dart',
    'lib/src/core/result/data_result.dart',
    'lib/src/core/ui/network_list_page.dart',
    'lib/src/data/mapper/wan_response_mapper.dart',
    'lib/src/data/network/service/wan_api_service.dart',
    'lib/src/data/repository/contract/article_repository.dart',
    'lib/src/data/repository/implementation/default_article_repository.dart',
    'lib/src/data/repository/implementation/default_search_suggestions_repository.dart',
    'lib/src/features/home/view/daily_questions_screen.dart',
    'lib/src/features/home/view/home_screen.dart',
    'lib/src/features/home/view/search_screen.dart',
    'lib/src/features/home/view_model/daily_questions_view_model.dart',
    'lib/src/features/home/view_model/home_view_model.dart',
    'lib/src/features/home/view_model/search_view_model.dart',
    'test/core/paging/paging_controller_test.dart',
    'test/core/result/wan_response_mapper_test.dart',
    'test/core/ui/network_list_page_test.dart',
    'test/data/repository/default_article_repository_test.dart',
    'test/data/repository/default_search_suggestions_repository_test.dart',
    'test/features/home/home_view_model_test.dart',
    'test/features/home/search_view_model_test.dart',
    'integration_test/stage2_navigation_test.dart',
    '.github/workflows/stage2.yml',
  ];
  final List<String> failures = <String>[];
  for (final String path in required) {
    if (!File('${root.path}/$path').existsSync()) {
      failures.add('Missing stage 2 file: $path');
    }
  }

  _expectContains(
    failures,
    'lib/src/data/network/service/wan_api_service.dart',
    "baseUrl: 'https://wanandroid.com/'",
  );
  _expectContains(
    failures,
    'lib/src/data/network/service/wan_api_service.dart',
    'followRedirects: false',
  );
  _expectContains(
    failures,
    'lib/src/app/bootstrap/bootstrap.dart',
    'DefaultArticleRepository(network)',
  );
  _expectContains(
    failures,
    'lib/src/app/bootstrap/bootstrap.dart',
    'SharedPreferencesSearchHistoryStorage()',
  );

  for (final String removed in <String>[
    'lib/src/data/repository/contract/home_repository.dart',
    'lib/src/data/repository/implementation/fake_home_repository.dart',
    'lib/src/model/home_feed.dart',
  ]) {
    if (File('${root.path}/$removed').existsSync()) {
      failures.add('Stage 1 Fake production path still exists: $removed');
    }
  }

  if (failures.isNotEmpty) {
    for (final String failure in failures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('Stage 2 structural check passed.');
}

void _expectContains(
  List<String> failures,
  String relativePath,
  String expected,
) {
  final File file = File('${Directory.current.path}/$relativePath');
  if (!file.existsSync() || !file.readAsStringSync().contains(expected)) {
    failures.add('$relativePath does not contain: $expected');
  }
}
