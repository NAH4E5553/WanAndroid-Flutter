import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/app/app.dart';
import 'package:wanandroid_flutter/src/app/bootstrap/app_dependencies.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/reader/reading_history_provider.dart';
import 'package:wanandroid_flutter/src/data/database/reading_history_database.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/avatar_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_article_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_reading_history_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_search_suggestions_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_topic_repository.dart';
import 'package:wanandroid_flutter/src/data/storage/search_history_storage.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/features/reader/view_model/reader_collection_view_model.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_dependencies.dart';

void bootstrap() {
  WidgetsFlutterBinding.ensureInitialized();
  final AppDependencies dependencies = buildAppDependencies();
  unawaited(dependencies.themeController.load());
  // Public browsing does not wait for restore, but the avatar startup chain
  // itself is deterministic: initialize (including orphan cleanup) and
  // session restore both finish before lost picker data is consumed.
  unawaited(_initializeAndRecoverAvatar(dependencies));
  final ReadingHistoryDatabase historyDatabase = ReadingHistoryDatabase();
  runApp(
    ProviderScope(
      retry: (int retryCount, Object error) => null,
      overrides: [
        themeControllerProvider.overrideWithValue(dependencies.themeController),
        authRepositoryProvider.overrideWithValue(dependencies.authRepository),
        collectionRepositoryProvider.overrideWithValue(
          dependencies.collectionRepository,
        ),
        readerCollectionViewModelProvider.overrideWithValue(
          ReaderCollectionViewModel(dependencies.collectionRepository),
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
        avatarRepositoryProvider.overrideWithValue(
          dependencies.avatarRepository,
        ),
      ],
      child: const WanAndroidApp(),
    ),
  );
}

/// Runs after the session restore finished: when a persisted pending avatar
/// operation survived a process kill and re-attributes to the verified
/// account, the repository exposes a recovery candidate and the app layer
/// navigates to the adjust page.
Future<void> _initializeAndRecoverAvatar(AppDependencies dependencies) async {
  await Future.wait<void>(<Future<void>>[
    dependencies.avatarRepository.initialize(),
    dependencies.authRepository.restore().then((_) {}),
  ]);
  final AuthStateView session = dependencies.authRepository.view();
  final AvatarIdentity? identity =
      (session.userId != null && session.accountVersionKey != null)
      ? AvatarIdentity(
          userId: session.userId!,
          accountVersionKey: session.accountVersionKey!,
        )
      : null;
  // No verified account: the repository clears the stale pending record.
  // On successful attribution the repository publishes recoveryReady and the
  // app layer navigates to the adjust page, then markRecoveryConsumed.
  await dependencies.avatarRepository.consumeRecoveredOperation(
    identity: identity,
  );
}
