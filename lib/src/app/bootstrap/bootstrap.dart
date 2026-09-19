import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/app/app.dart';
import 'package:wanandroid_flutter/src/data/network/article_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/network/service/wan_api_service.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_article_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_search_suggestions_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_topic_repository.dart';
import 'package:wanandroid_flutter/src/data/storage/search_history_storage.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_dependencies.dart';

void bootstrap() {
  WidgetsFlutterBinding.ensureInitialized();
  final ArticleNetworkDataSource network = DefaultArticleNetworkDataSource(
    DioWanApiService(),
  );
  runApp(
    ProviderScope(
      retry: (int retryCount, Object error) => null,
      overrides: [
        articleRepositoryProvider.overrideWithValue(
          DefaultArticleRepository(network),
        ),
        topicRepositoryProvider.overrideWithValue(
          DefaultTopicRepository(network),
        ),
        searchSuggestionsRepositoryProvider.overrideWithValue(
          DefaultSearchSuggestionsRepository(
            SharedPreferencesSearchHistoryStorage(),
            network,
          ),
        ),
      ],
      child: const WanAndroidApp(),
    ),
  );
}
