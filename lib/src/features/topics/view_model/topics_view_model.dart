import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_controller.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_state.dart';
import 'package:wanandroid_flutter/src/core/platform/app_visibility.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/topic_repository.dart';
import 'package:wanandroid_flutter/src/features/topics/state/topics_ui_state.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/topic.dart';

final NotifierProvider<TopicsViewModel, TopicsUiState> topicsViewModelProvider =
    NotifierProvider<TopicsViewModel, TopicsUiState>(TopicsViewModel.new);

class TopicsViewModel extends Notifier<TopicsUiState> {
  static const int maxCachedCategories = 8;

  final LinkedHashMap<int, PagingController<Article, int>> _pages =
      LinkedHashMap<int, PagingController<Article, int>>();
  final Map<int, int> _lastChild = <int, int>{};
  StreamSubscription<PagingSnapshot<Article, int>>? _pageSubscription;
  DefaultRequestCancellationController? _categoryCancellation;
  int _categoryGeneration = 0;
  bool _categoryBusy = false;
  bool _visible = false;

  @override
  TopicsUiState build() {
    _visible = ref.read(appVisibilityProvider).topicsVisible;
    ref.listen<AppVisibilityState>(appVisibilityProvider, (
      AppVisibilityState? previous,
      AppVisibilityState next,
    ) {
      setVisible(next.topicsVisible);
    });
    ref.onDispose(() {
      _categoryCancellation?.cancel();
      unawaited(_pageSubscription?.cancel());
      for (final PagingController<Article, int> controller in _pages.values) {
        unawaited(controller.dispose());
      }
    });
    unawaited(Future<void>.microtask(retryTopics));
    return const TopicsUiState();
  }

  Future<void> retryTopics() async {
    if (_categoryBusy) return;
    _categoryBusy = true;
    final int generation = ++_categoryGeneration;
    final DefaultRequestCancellationController cancellation =
        DefaultRequestCancellationController();
    _categoryCancellation = cancellation;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final TopicRepository repository = ref.read(topicRepositoryProvider);
      final DataResult<List<Topic>> result = await repository.topics(
        cancellation.signal,
      );
      cancellation.throwIfCancelled();
      if (generation != _categoryGeneration) return;
      switch (result) {
        case DataFailure<List<Topic>>(:final DataError error):
          state = state.copyWith(loading: false, error: error);
        case DataSuccess<List<Topic>>(:final List<Topic> value):
          _acceptTopics(value);
      }
    } on RequestCancelledException {
      // A hidden or disposed tab must not publish a late tree.
    } finally {
      if (generation == _categoryGeneration) {
        _categoryBusy = false;
        if (_visible && state.loading && cancellation.isCancelled) {
          unawaited(Future<void>.microtask(retryTopics));
        }
      }
    }
  }

  void _acceptTopics(List<Topic> topics) {
    final Map<int, Topic> unique = <int, Topic>{};
    for (final Topic topic in topics) {
      unique.putIfAbsent(topic.id, () => topic);
    }
    final Set<int> parentIds = unique.values
        .where((Topic topic) => topic.parentId == null)
        .map((Topic topic) => topic.id)
        .toSet();
    unique.removeWhere(
      (int _, Topic topic) =>
          topic.parentId != null && !parentIds.contains(topic.parentId),
    );
    final Set<int> childIds = unique.values
        .where((Topic topic) => topic.parentId != null)
        .map((Topic topic) => topic.id)
        .toSet();
    for (final int id in _pages.keys.toList(growable: false)) {
      if (!childIds.contains(id)) {
        unawaited(_pages.remove(id)!.dispose());
      }
    }
    _lastChild.removeWhere(
      (int parentId, int childId) =>
          !parentIds.contains(parentId) || !childIds.contains(childId),
    );
    final List<Topic> accepted = unique.values.toList(growable: false);
    final int? parentId = parentIds.contains(state.selectedParentId)
        ? state.selectedParentId
        : (parentIds.isEmpty ? null : parentIds.first);
    final List<Topic> children = accepted
        .where((Topic topic) => topic.parentId == parentId)
        .toList(growable: false);
    final int? selectedId =
        children.any((Topic topic) => topic.id == state.selectedId)
        ? state.selectedId
        : children.any((Topic topic) => topic.id == _lastChild[parentId])
        ? _lastChild[parentId]
        : (children.isEmpty ? null : children.first.id);
    unawaited(_pageSubscription?.cancel());
    if (state.selectedId != selectedId) {
      _pages[state.selectedId]?.pauseLoading();
    }
    state = TopicsUiState(
      topics: accepted,
      loading: false,
      selectedParentId: parentId,
      selectedId: selectedId,
      pageStates: <int, PagedState<Article>>{
        for (final MapEntry<int, PagingController<Article, int>> entry
            in _pages.entries)
          entry.key: entry.value.state.page,
      },
    );
    if (selectedId != null) _activate(selectedId);
  }

  void selectParent(int id) {
    if (state.selectedParentId == id ||
        !state.parents.any((Topic topic) => topic.id == id)) {
      return;
    }
    final List<Topic> children = state.topics
        .where((Topic topic) => topic.parentId == id)
        .toList(growable: false);
    final int? childId =
        children.any((Topic topic) => topic.id == _lastChild[id])
        ? _lastChild[id]
        : (children.isEmpty ? null : children.first.id);
    _changeSelection(parentId: id, childId: childId);
  }

  void selectChild(int parentId, int childId) {
    if (state.selectedParentId != parentId ||
        !state.tabs.any((Topic topic) => topic.id == childId) ||
        state.selectedId == childId) {
      return;
    }
    _changeSelection(parentId: parentId, childId: childId);
  }

  void _changeSelection({required int parentId, required int? childId}) {
    unawaited(_pageSubscription?.cancel());
    _pages[state.selectedId]?.pauseLoading();
    if (childId != null) _lastChild[parentId] = childId;
    state = state.copyWith(
      selectedParentId: parentId,
      selectedId: childId,
      clearSelectedId: childId == null,
    );
    if (childId != null) _activate(childId);
  }

  void _activate(int id) {
    final PagingController<Article, int> controller;
    final PagingController<Article, int>? cached = _pages.remove(id);
    if (cached != null) {
      controller = cached;
    } else {
      final TopicRepository repository = ref.read(topicRepositoryProvider);
      controller = PagingController<Article, int>(
        initialPage: 0,
        keyOf: (Article article) => article.id,
        initialContext: id,
        requestPage: (
          int categoryId,
          int page,
          RequestCancellation cancellation,
        ) => repository.articles(categoryId, page, cancellation),
      );
    }
    _pages[id] = controller;
    while (_pages.length > maxCachedCategories) {
      final int oldestId = _pages.keys.first;
      unawaited(_pages.remove(oldestId)!.dispose());
      state = state.copyWith(
        pageStates: Map<int, PagedState<Article>>.of(state.pageStates)
          ..remove(oldestId),
      );
    }
    _pageSubscription = controller.changes.listen((
      PagingSnapshot<Article, int> snapshot,
    ) {
      if (state.selectedId != id) return;
      state = state.copyWith(
        pageStates: <int, PagedState<Article>>{
          ...state.pageStates,
          id: snapshot.page,
        },
      );
    });
    if (_visible) {
      unawaited(controller.startInitialLoad());
      unawaited(controller.resumeLoading());
    }
  }

  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    if (!visible) {
      _categoryCancellation?.cancel();
      _pages[state.selectedId]?.pauseLoading();
    } else {
      if (state.loading && !_categoryBusy) unawaited(retryTopics());
      final PagingController<Article, int>? selected = _pages[state.selectedId];
      if (selected != null) {
        unawaited(selected.startInitialLoad());
        unawaited(selected.resumeLoading());
      }
    }
  }

  PagingController<Article, int>? _selected(int id) =>
      _visible && state.selectedId == id ? _pages[id] : null;

  Future<void> refresh(int id) =>
      _selected(id)?.refresh() ?? Future<void>.value();
  Future<void> retryInitial(int id) =>
      _selected(id)?.retryInitial() ?? Future<void>.value();
  Future<void> retryRefresh(int id) =>
      _selected(id)?.retryRefresh() ?? Future<void>.value();
  Future<void> loadMore(int id) =>
      _selected(id)?.loadMore() ?? Future<void>.value();
  Future<void> retryAppend(int id) =>
      _selected(id)?.retryAppend() ?? Future<void>.value();
  Future<void> continueAfterPause(int id) =>
      _selected(id)?.continueAfterPause() ?? Future<void>.value();
}
