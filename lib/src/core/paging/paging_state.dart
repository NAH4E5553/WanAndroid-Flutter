import 'package:wanandroid_flutter/src/core/result/data_result.dart';

sealed class LoadState {
  const LoadState();
}

final class LoadIdle extends LoadState {
  const LoadIdle();
}

final class LoadLoading extends LoadState {
  const LoadLoading();
}

final class LoadFailure extends LoadState {
  const LoadFailure(this.error);

  final DataError error;
}

class PagedState<T> {
  const PagedState({
    this.items = const <Never>[],
    this.initial = const LoadIdle(),
    this.refresh = const LoadIdle(),
    this.append = const LoadIdle(),
    this.nextPage,
    this.consecutiveNoProgress = 0,
    this.autoLoadPaused = false,
    this.datasetGeneration = 0,
  });

  final List<T> items;
  final LoadState initial;
  final LoadState refresh;
  final LoadState append;
  final int? nextPage;
  final int consecutiveNoProgress;
  final bool autoLoadPaused;
  final int datasetGeneration;

  bool get isInitialLoading => initial is LoadLoading;
  bool get isRefreshing => refresh is LoadLoading;
  bool get isLoadingMore => append is LoadLoading;
  DataError? get initialError => switch (initial) {
    LoadFailure(:final DataError error) => error,
    _ => null,
  };
  DataError? get refreshError => switch (refresh) {
    LoadFailure(:final DataError error) => error,
    _ => null,
  };
  DataError? get loadMoreError => switch (append) {
    LoadFailure(:final DataError error) => error,
    _ => null,
  };
  bool get canLoadMore => nextPage != null;
  bool get canAutoLoadMore =>
      canLoadMore &&
      initial is LoadIdle &&
      refresh is LoadIdle &&
      append is LoadIdle &&
      !autoLoadPaused;

  PagedState<T> copyWith({
    List<T>? items,
    LoadState? initial,
    LoadState? refresh,
    LoadState? append,
    int? nextPage,
    bool clearNextPage = false,
    int? consecutiveNoProgress,
    bool? autoLoadPaused,
    int? datasetGeneration,
  }) => PagedState<T>(
    items: items ?? this.items,
    initial: initial ?? this.initial,
    refresh: refresh ?? this.refresh,
    append: append ?? this.append,
    nextPage: clearNextPage ? null : nextPage ?? this.nextPage,
    consecutiveNoProgress: consecutiveNoProgress ?? this.consecutiveNoProgress,
    autoLoadPaused: autoLoadPaused ?? this.autoLoadPaused,
    datasetGeneration: datasetGeneration ?? this.datasetGeneration,
  );
}

class PagingSnapshot<T, C> {
  const PagingSnapshot({required this.context, this.page = const PagedState()});

  final C context;
  final PagedState<T> page;

  PagingSnapshot<T, C> copyWith({C? context, PagedState<T>? page}) =>
      PagingSnapshot<T, C>(
        context: context ?? this.context,
        page: page ?? this.page,
      );
}
