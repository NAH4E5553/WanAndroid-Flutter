import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/search_suggestions_repository.dart';

final Provider<ArticleRepository> articleRepositoryProvider =
    Provider<ArticleRepository>(
      (Ref ref) => throw StateError(
        'ArticleRepository must be provided by the application bootstrap.',
      ),
    );

final Provider<SearchSuggestionsRepository>
searchSuggestionsRepositoryProvider = Provider<SearchSuggestionsRepository>(
  (Ref ref) => throw StateError(
    'SearchSuggestionsRepository must be provided by the application bootstrap.',
  ),
);

final Provider<String> homeChildRouteInstanceProvider = Provider<String>(
  (Ref ref) => throw StateError('A home child route instance is required.'),
);
