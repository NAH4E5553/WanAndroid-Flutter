import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/app/app.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/diagnostics/startup_metrics.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/reader/reading_history_provider.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/startup/startup_reveal_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/data/database/reading_history_database.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_reading_history_repository.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/features/reader/view_model/reader_collection_view_model.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_dependencies.dart';
import 'package:wanandroid_flutter/src/model/topic.dart';

import '../test/support/fake_avatar_dependencies.dart';
import '../test/support/fake_session_repositories.dart';
import '../test/support/fixed_topic_repository.dart';
import 'startup_review_fakes.dart';

/// STARTUP-02 连续录屏与 MI9 Profile 性能对照的独立固定 Fake 启动入口。
///
/// 复用生产的 [WanAndroidApp]/Router/HomeViewModel/启动层与原生资源,
/// 仅替换仓储与主题持久化,不引入 IntegrationTestBinding,因此与
/// 生产入口之间唯一的差异就是本文件中的这些 override。
///
/// 入口差异由编译期开关控制(构建命令会随证据一并交付):
/// - `STARTUP_REVIEW_DELAY_MS`:文章/问答共同的就绪延迟毫秒数,
///   默认 0(快速就绪);性能对照的延迟场景使用 800。
/// - `STARTUP_REVIEW_NO_ANIM`:为 true 时把原启动控制器预置为 done,
///   省略 Flutter 启动遮挡/动画,作为无动画对照组;生产默认为 false。
const int _reviewDelayMs = int.fromEnvironment('STARTUP_REVIEW_DELAY_MS');
const bool _reviewNoAnimation = bool.fromEnvironment('STARTUP_REVIEW_NO_ANIM');

void main() {
  StartupMetrics.instance.start();
  WidgetsFlutterBinding.ensureInitialized();
  StartupMetrics.instance.attach();
  StartupMetrics.instance.mark('binding_ready');
  final ThemeController themeController = ThemeController(
    preferences: const StartupReviewThemeStorage(),
  );
  unawaited(themeController.load());
  final ArticleRepository articleRepository = StartupReviewArticleRepository(
    delay: Duration(milliseconds: _reviewDelayMs),
  );
  StartupMetrics.instance.mark('dependencies_ready');
  final StartupRevealController? preDoneController = _reviewNoAnimation
      ? _preDoneController()
      : null;
  runApp(
    ProviderScope(
      retry: (int retryCount, Object error) => null,
      overrides: [
        themeControllerProvider.overrideWithValue(themeController),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        avatarRepositoryProvider.overrideWithValue(FakeAvatarRepository()),
        collectionRepositoryProvider.overrideWithValue(
          FakeCollectionRepository(),
        ),
        articleRepositoryProvider.overrideWithValue(articleRepository),
        topicRepositoryProvider.overrideWithValue(
          _DelayedTopicRepository(Duration(milliseconds: _reviewDelayMs)),
        ),
        searchSuggestionsRepositoryProvider.overrideWithValue(
          const StartupReviewSearchSuggestions(),
        ),
        readingHistoryRepositoryProvider.overrideWithValue(
          DefaultReadingHistoryRepository(ReadingHistoryDatabase()),
        ),
        readerCollectionViewModelProvider.overrideWithValue(
          ReaderCollectionViewModel(FakeCollectionRepository()),
        ),
        if (preDoneController != null)
          startupRevealControllerProvider.overrideWithValue(preDoneController),
      ],
      child: const WanAndroidApp(),
    ),
  );
  StartupMetrics.instance.mark('run_app');
}

/// 无动画对照组的控制器:与实验组同一个 [StartupRevealController] 生产类,
/// 仅在 runApp 之前经公开相位推进方法直接到达 done
///(reduce-motion 路径跳过揭幕后立即完成退出),
/// 因此首帧起内容可见、首页测点资格与生产一致,不修改任何动画参数。
StartupRevealController _preDoneController() {
  final StartupRevealController controller = StartupRevealController();
  controller.markFirstFrame(reduceMotion: true);
  controller.markExitFinished();
  return controller;
}

/// 专题仓储与文章/问答保持同一就绪延迟,使场景条件一致;
/// 未覆写的方法沿用 [FixedTopicRepository] 的固定行为。
class _DelayedTopicRepository extends FixedTopicRepository {
  _DelayedTopicRepository(this._delay);

  final Duration _delay;

  @override
  Future<DataResult<List<Topic>>> topics(
    RequestCancellation cancellation,
  ) async {
    await Future<void>.delayed(_delay);
    return super.topics(cancellation);
  }
}
