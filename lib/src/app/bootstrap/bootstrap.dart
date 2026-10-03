import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/app/app.dart';
import 'package:wanandroid_flutter/src/app/bootstrap/app_dependencies.dart';
import 'package:wanandroid_flutter/src/core/diagnostics/startup_metrics.dart';
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
  StartupMetrics.instance.attach();
  StartupMetrics.instance.mark('binding_ready');
  final AppDependencies dependencies = buildAppDependencies();
  unawaited(dependencies.themeController.load());
  // 公开浏览不等待恢复,但头像启动链本身是确定性的:
  // 初始化(包括孤儿清理)与会话恢复都会完成,
  // 之后才会消费丢失的选择器数据。
  unawaited(_initializeAndRecoverAvatar(dependencies));
  final ReadingHistoryDatabase historyDatabase = ReadingHistoryDatabase();
  StartupMetrics.instance.mark('dependencies_ready');
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
  StartupMetrics.instance.mark('run_app');
}

/// 在会话恢复完成后运行:当一条持久化的待处理头像操作
/// 在进程被杀后幸存,并重新归属到已验证账号时,
/// 仓储会暴露一个恢复候选,app 层
/// 随之导航到调整页。
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
  // 没有已验证账号:仓储清除过期的待处理记录。
  // 归属成功时,仓储发布 recoveryReady,app 层导航到调整页,
  // 之后调用 markRecoveryConsumed。
  await dependencies.avatarRepository.consumeRecoveredOperation(
    identity: identity,
  );
}
