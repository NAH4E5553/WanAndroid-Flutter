import 'package:wanandroid_flutter/src/core/paging/paging_state.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/search_history.dart';

class SearchSuggestionsState {
  const SearchSuggestionsState({
    this.history = const SearchHistory(),
    this.hotKeys = const <String>[],
    this.hotLoading = true,
    this.hotError,
    this.historyWriteFailed = false,
  });

  final SearchHistory history;
  final List<String> hotKeys;
  final bool hotLoading;
  final DataError? hotError;
  final bool historyWriteFailed;

  SearchSuggestionsState copyWith({
    SearchHistory? history,
    List<String>? hotKeys,
    bool? hotLoading,
    DataError? hotError,
    bool clearHotError = false,
    bool? historyWriteFailed,
  }) => SearchSuggestionsState(
    history: history ?? this.history,
    hotKeys: hotKeys ?? this.hotKeys,
    hotLoading: hotLoading ?? this.hotLoading,
    hotError: clearHotError ? null : hotError ?? this.hotError,
    historyWriteFailed: historyWriteFailed ?? this.historyWriteFailed,
  );
}

class SearchUiState {
  const SearchUiState({
    this.input = '',
    this.keyword = '',
    this.page = const PagedState<Article>(),
    this.suggestions = const SearchSuggestionsState(),
    this.isEditing = true,
  });

  final String input;
  final String keyword;
  final PagedState<Article> page;
  final SearchSuggestionsState suggestions;
  final bool isEditing;

  bool get hasSubmitted => keyword.isNotEmpty;
  bool get canSubmit => input.trim().isNotEmpty;
  bool get showResults => hasSubmitted && !isEditing && input.trim() == keyword;

  SearchUiState copyWith({
    String? input,
    String? keyword,
    PagedState<Article>? page,
    SearchSuggestionsState? suggestions,
    bool? isEditing,
  }) => SearchUiState(
    input: input ?? this.input,
    keyword: keyword ?? this.keyword,
    page: page ?? this.page,
    suggestions: suggestions ?? this.suggestions,
    isEditing: isEditing ?? this.isEditing,
  );
}
