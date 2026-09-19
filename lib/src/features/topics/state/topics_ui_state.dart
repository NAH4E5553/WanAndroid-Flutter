import 'package:wanandroid_flutter/src/core/paging/paging_state.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/topic.dart';

class TopicsUiState {
  const TopicsUiState({
    this.topics = const <Topic>[],
    this.loading = true,
    this.error,
    this.selectedParentId,
    this.selectedId,
    this.pageStates = const <int, PagedState<Article>>{},
  });

  final List<Topic> topics;
  final bool loading;
  final DataError? error;
  final int? selectedParentId;
  final int? selectedId;
  final Map<int, PagedState<Article>> pageStates;

  List<Topic> get parents => topics
      .where((Topic topic) => topic.parentId == null)
      .toList(growable: false);

  List<Topic> get tabs => topics
      .where((Topic topic) => topic.parentId == selectedParentId)
      .toList(growable: false);

  PagedState<Article> get selectedPage =>
      pageStates[selectedId] ?? const PagedState<Article>();

  TopicsUiState copyWith({
    List<Topic>? topics,
    bool? loading,
    DataError? error,
    bool clearError = false,
    int? selectedParentId,
    int? selectedId,
    bool clearSelectedId = false,
    Map<int, PagedState<Article>>? pageStates,
  }) => TopicsUiState(
    topics: topics ?? this.topics,
    loading: loading ?? this.loading,
    error: clearError ? null : error ?? this.error,
    selectedParentId: selectedParentId ?? this.selectedParentId,
    selectedId: clearSelectedId ? null : selectedId ?? this.selectedId,
    pageStates: pageStates ?? this.pageStates,
  );
}
