import 'dart:async';

import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_state.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

enum _PagingOperation { initial, refresh, automatic, manualContinue }

class _PagingRequest {
  const _PagingRequest({
    required this.id,
    required this.page,
    required this.operation,
    required this.cancellation,
  });

  final int id;
  final int page;
  final _PagingOperation operation;
  final DefaultRequestCancellationController cancellation;
}

class PagingController<T, C> {
  PagingController({
    required this.initialPage,
    required this.keyOf,
    required C initialContext,
    required this.requestPage,
  }) : _state = PagingSnapshot<T, C>(context: initialContext);

  final int initialPage;
  final Object Function(T item) keyOf;
  final Future<DataResult<PageResult<T>>> Function(
    C context,
    int page,
    RequestCancellation cancellation,
  )
  requestPage;

  final StreamController<PagingSnapshot<T, C>> _changes =
      StreamController<PagingSnapshot<T, C>>.broadcast(sync: true);
  final Set<int> _automaticPages = <int>{};
  PagingSnapshot<T, C> _state;
  _PagingRequest? _active;
  _PagingRequest? _failed;
  _PagingRequest? _suspended;
  int _generation = 0;
  bool _started = false;
  bool _disposed = false;

  PagingSnapshot<T, C> get state => _state;
  Stream<PagingSnapshot<T, C>> get changes => _changes.stream;

  Future<void> startInitialLoad() {
    if (_started || _disposed) {
      return Future<void>.value();
    }
    _started = true;
    return _replace();
  }

  Future<void> reset(C context) {
    if (_disposed) {
      return Future<void>.value();
    }
    _invalidateActive();
    _failed = null;
    _automaticPages.clear();
    _started = true;
    _publish(
      PagingSnapshot<T, C>(
        context: context,
        page: PagedState<T>(
          initial: const LoadLoading(),
          datasetGeneration: _state.page.datasetGeneration + 1,
        ),
      ),
    );
    return _launch(initialPage, _PagingOperation.initial);
  }

  Future<void> refresh() {
    if (_disposed) {
      return Future<void>.value();
    }
    _started = true;
    return _replace();
  }

  Future<void> retryInitial() => _retry(_PagingOperation.initial);
  Future<void> retryRefresh() => _retry(_PagingOperation.refresh);

  Future<void> retryAppend() {
    final _PagingRequest? failure = _failed;
    if (failure == null ||
        (failure.operation != _PagingOperation.automatic &&
            failure.operation != _PagingOperation.manualContinue) ||
        _active != null ||
        _disposed) {
      return Future<void>.value();
    }
    return _launch(failure.page, failure.operation);
  }

  Future<void> loadMore() {
    final PagedState<T> pageState = _state.page;
    final int? page = pageState.nextPage;
    if (_disposed ||
        page == null ||
        _active != null ||
        !pageState.canAutoLoadMore ||
        !_automaticPages.add(page)) {
      return Future<void>.value();
    }
    return _launch(page, _PagingOperation.automatic);
  }

  Future<void> continueAfterPause() {
    final PagedState<T> pageState = _state.page;
    final int? page = pageState.nextPage;
    if (_disposed ||
        page == null ||
        _active != null ||
        !pageState.autoLoadPaused ||
        pageState.loadMoreError != null) {
      return Future<void>.value();
    }
    return _launch(page, _PagingOperation.manualContinue);
  }

  void pauseLoading() {
    final _PagingRequest? request = _active;
    if (request == null || _disposed) {
      return;
    }
    _suspended = request;
    _active = null;
    request.cancellation.cancel();
  }

  Future<void> resumeLoading() {
    final _PagingRequest? request = _suspended;
    if (request == null || _disposed) {
      return Future<void>.value();
    }
    _suspended = null;
    return _launch(request.page, request.operation);
  }

  Future<void> _retry(_PagingOperation operation) {
    if (_disposed || _active != null || _failed?.operation != operation) {
      return Future<void>.value();
    }
    return _replace();
  }

  Future<void> _replace() {
    _invalidateActive();
    final _PagingOperation operation = _state.page.items.isEmpty
        ? _PagingOperation.initial
        : _PagingOperation.refresh;
    return _launch(initialPage, operation);
  }

  void _invalidateActive() {
    _generation += 1;
    _active?.cancellation.cancel();
    _active = null;
    _suspended = null;
  }

  Future<void> _launch(int page, _PagingOperation operation) async {
    if (_disposed) {
      return;
    }
    _suspended = null;
    final _PagingRequest request = _PagingRequest(
      id: ++_generation,
      page: page,
      operation: operation,
      cancellation: DefaultRequestCancellationController(),
    );
    _active = request;
    _failed = null;
    final PagedState<T> previous = _state.page;
    final PagedState<T> loading = switch (operation) {
      _PagingOperation.initial => PagedState<T>(
        initial: const LoadLoading(),
        datasetGeneration: previous.datasetGeneration,
      ),
      _PagingOperation.refresh => previous.copyWith(
        initial: const LoadIdle(),
        refresh: const LoadLoading(),
        append: const LoadIdle(),
        consecutiveNoProgress: 0,
        autoLoadPaused: false,
      ),
      _PagingOperation.automatic ||
      _PagingOperation.manualContinue => previous.copyWith(
        initial: const LoadIdle(),
        refresh: const LoadIdle(),
        append: const LoadLoading(),
        autoLoadPaused: false,
      ),
    };
    _publish(_state.copyWith(page: loading));

    DataResult<PageResult<T>> result;
    try {
      result = await requestPage(
        _state.context,
        page,
        request.cancellation.signal,
      );
      request.cancellation.throwIfCancelled();
    } on RequestCancelledException {
      return;
    } catch (_) {
      result = DataFailure<PageResult<T>>(DataError.invalidResponse);
    }
    if (_disposed || _active != request) {
      return;
    }
    switch (result) {
      case DataFailure<PageResult<T>>(:final DataError error):
        _finishFailure(request, error);
      case DataSuccess<PageResult<T>>(:final PageResult<T> value):
        if (value.nextPage != null && value.nextPage! <= page) {
          _finishFailure(request, DataError.invalidResponse);
        } else {
          _finishSuccess(request, value);
        }
    }
  }

  void _finishFailure(_PagingRequest request, DataError error) {
    _active = null;
    _failed = request;
    final LoadFailure failure = LoadFailure(error);
    final PagedState<T> current = _state.page;
    final PagedState<T> next = switch (request.operation) {
      _PagingOperation.initial => current.copyWith(initial: failure),
      _PagingOperation.refresh => current.copyWith(refresh: failure),
      _PagingOperation.automatic ||
      _PagingOperation.manualContinue => current.copyWith(append: failure),
    };
    _publish(_state.copyWith(page: next));
  }

  void _finishSuccess(_PagingRequest request, PageResult<T> result) {
    final PagedState<T> current = _state.page;
    final bool replacing =
        request.operation == _PagingOperation.initial ||
        request.operation == _PagingOperation.refresh;
    final Map<Object, T> merged = <Object, T>{};
    if (!replacing) {
      for (final T item in current.items) {
        merged[keyOf(item)] = item;
      }
    }
    final int oldSize = merged.length;
    for (final T item in result.items) {
      merged[keyOf(item)] = item;
    }
    final bool madeProgress = merged.length > oldSize;
    final int noProgress = replacing || madeProgress || result.nextPage == null
        ? 0
        : current.consecutiveNoProgress + 1;
    final bool paused =
        result.nextPage != null &&
        !replacing &&
        !madeProgress &&
        (noProgress >= 2 ||
            request.operation == _PagingOperation.manualContinue);
    if (replacing) {
      _automaticPages.clear();
    }
    _active = null;
    _failed = null;
    _publish(
      _state.copyWith(
        page: PagedState<T>(
          items: merged.values.toList(growable: false),
          nextPage: result.nextPage,
          consecutiveNoProgress: noProgress,
          autoLoadPaused: paused,
          datasetGeneration: current.datasetGeneration + (replacing ? 1 : 0),
        ),
      ),
    );
  }

  void _publish(PagingSnapshot<T, C> value) {
    if (_disposed) {
      return;
    }
    _state = value;
    _changes.add(value);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _active?.cancellation.cancel();
    _active = null;
    _suspended = null;
    await _changes.close();
  }
}
