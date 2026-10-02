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
  /// Whether a startup overlay currently covers the screen. Defaults to the
  /// core startup controller's live answer (no instance means nothing covers
  /// the screen), and the composition root may override the predicate for
  /// tests. The answer is captured per build — a later transition must not
  /// relabel an occluded raster.
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
    // Startup handoff (core controller): when the occluding layer reaches its
    // terminal phase, republish the current snapshot so the rebuilt home
    // screen reports its frame inside the removal frame's build window. The
    // static hook (not a provider) keeps no Timer alive in layered-free
    // hosts, and the covered predicate already captured the per-build
    // answer, so a frame built while covered can never be retroactively
    // relabeled.
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

  /// Publishes a fresh immutable snapshot of the current state (new
  /// identity, same content). Used by the composition root when the startup
  /// layer is removed: the rebuilt home screen reports its frame inside that
  /// removal frame's build window, so a ready page is measured on the frame
  /// where it actually becomes visible.
  void republish() {
    if (!ref.mounted) return;
    if (const bool.fromEnvironment('STARTUP_DBG')) {
      // ignore: avoid_print
      print('DBG republish');
    }
    state = state.copyWith();
  }

  /// View forwards its build snapshot; completion is tied to its raster
  /// frame AND to this build's actual visibility: a snapshot built while the
  /// startup overlay covered the screen stays ineligible even if the overlay
  /// ends right after (no retroactive relabeling).
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
      // Replacement, invisibility and disposal intentionally discard results.
    }
  }
}
