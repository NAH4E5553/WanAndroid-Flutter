import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_controller.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_state.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/features/home/state/search_ui_state.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/search_history.dart';

const int maxSearchLength = 200;

final NotifierProvider<SearchViewModel, SearchUiState> searchViewModelProvider =
    NotifierProvider<SearchViewModel, SearchUiState>(
      SearchViewModel.new,
      dependencies: [homeChildRouteInstanceProvider],
      isAutoDispose: true,
    );

class SearchViewModel extends Notifier<SearchUiState> {
  late final PagingController<Article, String> _paging;
  StreamSubscription<PagingSnapshot<Article, String>>? _pagingSubscription;
  DefaultRequestCancellationController? _hotKeyCancellation;

  @override
  SearchUiState build() {
    ref.watch(homeChildRouteInstanceProvider);
    final ArticleRepository articles = ref.read(articleRepositoryProvider);
    _paging = PagingController<Article, String>(
      initialPage: 0,
      keyOf: (Article article) => article.id,
      initialContext: '',
      requestPage: (
        String keyword,
        int page,
        RequestCancellation cancellation,
      ) => articles.search(page, keyword, cancellation),
    );
    _pagingSubscription = _paging.changes.listen((
      PagingSnapshot<Article, String> snapshot,
    ) {
      state = state.copyWith(keyword: snapshot.context, page: snapshot.page);
    });
    ref.onDispose(() {
      _hotKeyCancellation?.cancel();
      unawaited(_pagingSubscription?.cancel());
      unawaited(_paging.dispose());
    });
    unawaited(Future<void>.microtask(_loadSuggestions));
    return const SearchUiState();
  }

  void editInput(String value) {
    final String text = _take(value, maxSearchLength);
    if (text == state.input) return;
    state = state.copyWith(input: text, isEditing: true);
  }

  Future<void> submit() async {
    final String keyword = state.input.trim();
    if (keyword.isEmpty) return;
    state = state.copyWith(isEditing: false);
    if (keyword == _paging.state.context) {
      final PagedState<Article> page = _paging.state.page;
      if (page.isInitialLoading || page.isRefreshing || page.isLoadingMore) {
        return;
      }
      unawaited(_paging.refresh());
    } else {
      unawaited(_paging.reset(keyword));
    }
    final bool saved = await ref
        .read(searchSuggestionsRepositoryProvider)
        .record(keyword);
    if (!ref.mounted) return;
    state = state.copyWith(
      suggestions: state.suggestions.copyWith(historyWriteFailed: !saved),
    );
    await _loadHistory();
  }

  Future<void> selectKeyword(String keyword) async {
    editInput(keyword);
    await submit();
  }

  Future<void> clearHistory() async {
    final bool cleared = await ref
        .read(searchSuggestionsRepositoryProvider)
        .clearHistory();
    if (!ref.mounted) return;
    state = state.copyWith(
      suggestions: state.suggestions.copyWith(historyWriteFailed: !cleared),
    );
    await _loadHistory();
  }

  Future<void> retrySuggestions() => _loadSuggestions();
  Future<void> refresh() =>
      _paging.state.context.isEmpty ? Future<void>.value() : _paging.refresh();
  Future<void> retryInitial() => _paging.retryInitial();
  Future<void> retryRefresh() => _paging.retryRefresh();
  Future<void> loadMore() => _paging.loadMore();
  Future<void> retryLoadMore() => _paging.retryAppend();
  Future<void> continueAfterPause() => _paging.continueAfterPause();

  Future<void> _loadSuggestions() async {
    await Future.wait<void>(<Future<void>>[_loadHistory(), _loadHotKeys()]);
  }

  Future<void> _loadHistory() async {
    final SearchHistory history = await ref
        .read(searchSuggestionsRepositoryProvider)
        .loadHistory();
    if (!ref.mounted) return;
    state = state.copyWith(
      suggestions: state.suggestions.copyWith(history: history),
    );
  }

  Future<void> _loadHotKeys() async {
    _hotKeyCancellation?.cancel();
    final DefaultRequestCancellationController cancellation =
        DefaultRequestCancellationController();
    _hotKeyCancellation = cancellation;
    state = state.copyWith(
      suggestions: state.suggestions.copyWith(
        hotLoading: true,
        clearHotError: true,
      ),
    );
    try {
      final DataResult<List<String>> result = await ref
          .read(searchSuggestionsRepositoryProvider)
          .hotKeys(cancellation.signal);
      cancellation.throwIfCancelled();
      if (!ref.mounted) return;
      state = state.copyWith(
        suggestions: switch (result) {
          DataSuccess<List<String>>(:final List<String> value) =>
            state.suggestions.copyWith(
              hotKeys: value,
              hotLoading: false,
              clearHotError: true,
            ),
          DataFailure<List<String>>(:final DataError error) =>
            state.suggestions.copyWith(hotLoading: false, hotError: error),
        },
      );
    } on RequestCancelledException {
      // A replacement load or route disposal owns the newer state.
    }
  }
}

String _take(String value, int maxLength) =>
    value.length <= maxLength ? value : value.substring(0, maxLength);
