import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_controller.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_state.dart';
import 'package:wanandroid_flutter/src/core/platform/app_visibility.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/features/home/state/home_ui_state.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

final NotifierProvider<HomeViewModel, HomeUiState> homeViewModelProvider =
    NotifierProvider<HomeViewModel, HomeUiState>(HomeViewModel.new);

class HomeViewModel extends Notifier<HomeUiState> {
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
