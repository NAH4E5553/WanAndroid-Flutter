import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/diagnostics/startup_metrics.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_controller.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_state.dart';
import 'package:wanandroid_flutter/src/core/platform/app_visibility.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/startup/startup_reveal_controller.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/features/home/state/home_ui_state.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

final NotifierProvider<HomeViewModel, HomeUiState> homeViewModelProvider =
    NotifierProvider<HomeViewModel, HomeUiState>(HomeViewModel.new);

class HomeViewModel extends Notifier<HomeUiState> {
  /// 当前是否有启动遮罩正覆盖屏幕。默认取核心启动控制器的实时答案
  /// （没有实例即代表没有内容覆盖屏幕），组合根也可以为测试覆盖
  /// 该判定函数。答案按每次 build 捕获——之后再发生的
  /// 状态切换不得重新标注一张被遮挡的
  /// 光栅帧。
  bool Function() startupCovered = () => StartupRevealController.coveredNow;

  late final PagingController<Article, void> _articles;
  StreamSubscription<PagingSnapshot<Article, void>>? _articleSubscription;
  DefaultRequestCancellationController? _questionCancellation;
  int _questionGeneration = 0;
  bool _visible = true;

  @override
  HomeUiState build() {
    _visible = ref.read(appVisibilityProvider).homeVisible;
    ref.listen<AppVisibilityState>(appVisibilityProvider, (
      AppVisibilityState? previous,
      AppVisibilityState next,
    ) {
      setVisible(next.homeVisible);
    });
    // 启动交接（核心控制器）：当遮罩层到达终止阶段时，重新发布
    // 当前快照，使重建后的首页能在移除帧的 build 窗口内
    // 上报自己的帧。静态钩子（而非 Provider）在无层级的
    // 宿主中不会让任何 Timer 存活，而覆盖判定函数
    // 已经捕获了按 build 的答案，因此在被覆盖期间
    // 构建的帧绝不会被追溯地
    // 重新标注。
    StartupRevealController.onDone = _onStartupDone;
    ref.onDispose(() {
      if (identical(StartupRevealController.onDone, _onStartupDone)) {
        StartupRevealController.onDone = null;
      }
    });
    final ArticleRepository repository = ref.read(articleRepositoryProvider);
    _articles = PagingController<Article, void>(
      initialPage: 0,
      keyOf: (Article article) => article.id,
      initialContext: null,
      requestPage: (void _, int page, RequestCancellation cancellation) =>
          repository.articles(page, cancellation),
    );
    _articleSubscription = _articles.changes.listen((
      PagingSnapshot<Article, void> snapshot,
    ) {
      state = state.copyWith(articles: snapshot.page);
    });
    ref.onDispose(() {
      _questionCancellation?.cancel();
      unawaited(_articleSubscription?.cancel());
      unawaited(_articles.dispose());
    });
    unawaited(Future<void>.microtask(_articles.startInitialLoad));
    unawaited(Future<void>.microtask(_requestQuestions));
    return HomeUiState(visible: _visible);
  }

  void _onStartupDone() {
    republish();
  }

  /// 发布当前状态的一个全新的不可变快照（新身份，内容相同）。
  /// 供组合根在启动层被移除时使用：重建后的首页在该移除
  /// 帧的 build 窗口内上报自己的帧，因此就绪页面会在它真正
  /// 变得可见的那一帧上
  /// 被测量。
  void republish() {
    if (!ref.mounted) return;
    if (const bool.fromEnvironment('STARTUP_DBG')) {
      // ignore: avoid_print
      print('DBG republish');
    }
    state = state.copyWith();
  }

  /// View 转发它的 build 快照；完成判定同时绑定到它的光栅帧
  /// 以及本次 build 的实际可见性：在启动遮罩覆盖屏幕期间构建的
  /// 快照始终保持不合格，即使遮罩在紧随其后
  /// 就结束（不做追溯性的重新标注）。
  void reportStartupFrame(HomeUiState snapshot) {
    final StartupMetrics metrics = StartupMetrics.instance;
    if (!metrics.enabled || !snapshot.visible) return;
    final bool coveredAtBuild = startupCovered();
    bool valid() =>
        ref.mounted &&
        identical(state, snapshot) &&
        state.visible &&
        !coveredAtBuild;
    metrics.frame('home_first_raster', stillValid: valid);
    if (snapshot.articles.isInitialLoading) return;
    final String articleOutcome = snapshot.articles.initialError != null
        ? 'error'
        : snapshot.articles.items.isEmpty
        ? 'empty'
        : 'success';
    metrics.frame(
      'home_articles_raster',
      outcome: articleOutcome,
      stillValid: valid,
    );
    if (articleOutcome == 'error') {
      metrics.frame(
        'home_terminal_raster',
        outcome: 'error',
        stillValid: valid,
      );
      return;
    }
    if (snapshot.questions.loading) return;
    final String outcome = snapshot.questions.error != null
        ? 'error'
        : articleOutcome == 'empty' || snapshot.questions.items.isEmpty
        ? 'empty'
        : 'success';
    metrics.frame('home_terminal_raster', outcome: outcome, stillValid: valid);
    if (outcome != 'error') {
      metrics.frame('home_content_raster', outcome: outcome, stillValid: valid);
    }
  }

  Future<void> refresh() async {
    if (!_visible) return;
    await Future.wait<void>(<Future<void>>[
      _articles.refresh(),
      _requestQuestions(),
    ]);
  }

  Future<void> retryInitial() => _articles.retryInitial();
  Future<void> retryRefresh() => _articles.retryRefresh();
  Future<void> loadMore() => _articles.loadMore();
  Future<void> retryLoadMore() => _articles.retryAppend();
  Future<void> continueAfterPause() => _articles.continueAfterPause();
  Future<void> retryQuestions() => _requestQuestions();

  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    state = state.copyWith(visible: visible);
    if (visible) {
      unawaited(_articles.resumeLoading());
      if (state.questions.loading) unawaited(_requestQuestions());
    } else {
      _articles.pauseLoading();
      _questionCancellation?.cancel();
    }
  }

  Future<void> _requestQuestions() async {
    if (!_visible) return;
    final int generation = ++_questionGeneration;
    _questionCancellation?.cancel();
    final DefaultRequestCancellationController cancellation =
        DefaultRequestCancellationController();
    _questionCancellation = cancellation;
    state = state.copyWith(
      questions: QuestionUiState(items: state.questions.items, loading: true),
    );
    try {
      final DataResult<List<Article>> result = await ref
          .read(articleRepositoryProvider)
          .questions(cancellation.signal);
      cancellation.throwIfCancelled();
      if (generation != _questionGeneration) return;
      state = state.copyWith(
        questions: switch (result) {
          DataSuccess<List<Article>>(:final List<Article> value) =>
            QuestionUiState(items: value, loading: false),
          DataFailure<List<Article>>(:final DataError error) => QuestionUiState(
            items: state.questions.items,
            loading: false,
            error: error,
          ),
        },
      );
    } on RequestCancelledException {
      // 被替换、不可见与销毁时有意丢弃结果。
    }
  }
}
