import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/app/app.dart';
import 'package:wanandroid_flutter/src/app/bootstrap/app_dependencies.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/reader/reading_history_provider.dart';
import 'package:wanandroid_flutter/src/data/database/reading_history_database.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_article_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_reading_history_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_search_suggestions_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_topic_repository.dart';
import 'package:wanandroid_flutter/src/data/storage/search_history_storage.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_dependencies.dart';

void bootstrap() {
  WidgetsFlutterBinding.ensureInitialized();
  final AppDependencies dependencies = buildAppDependencies();
  unawaited(dependencies.themeController.load());
  // Restore runs through the session coordinator; public browsing never
  // waits for it.
  unawaited(dependencies.authRepository.restore());
  final ReadingHistoryDatabase historyDatabase = ReadingHistoryDatabase();
  runApp(
    ProviderScope(
      retry: (int retryCount, Object error) => null,
      overrides: [
        themeControllerProvider.overrideWithValue(dependencies.themeController),
        sessionStoreProvider.overrideWithValue(dependencies.sessionStore),
        authRepositoryProvider.overrideWithValue(dependencies.authRepository),
        collectionRepositoryProvider.overrideWithValue(
          dependencies.collectionRepository,
        ),
        readingHistoryRepositoryProvider.overrideWithValue(
          DefaultReadingHistoryRepository(historyDatabase),
        ),
        articleRepositoryProvider.overrideWithValue(
          DefaultArticleRepository(
            dependencies.network,
            dependencies.collectionRepository,
          ),
        ),
        topicRepositoryProvider.overrideWithValue(
          DefaultTopicRepository(
            dependencies.network,
            dependencies.collectionRepository,
          ),
        ),
        searchSuggestionsRepositoryProvider.overrideWithValue(
          DefaultSearchSuggestionsRepository(
            SharedPreferencesSearchHistoryStorage(),
            dependencies.network,
          ),
        ),
      ],
      child: const WanAndroidApp(),
    ),
  );
}
