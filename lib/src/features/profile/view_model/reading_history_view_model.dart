import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/reader/reading_history_provider.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/reading_history_repository.dart';
import 'package:wanandroid_flutter/src/model/reading_history_entry.dart';

final NotifierProvider<ReadingHistoryViewModel, ReadingHistoryUiState>
readingHistoryViewModelProvider =
    NotifierProvider.autoDispose<
      ReadingHistoryViewModel,
      ReadingHistoryUiState
    >(ReadingHistoryViewModel.new);

class ReadingHistoryUiState {
  const ReadingHistoryUiState({
    this.entries = const <ReadingHistoryEntry>[],
    this.loading = true,
    this.hasMore = true,
    this.error,
  });

  final List<ReadingHistoryEntry> entries;
  final bool loading;
  final bool hasMore;
  final Object? error;

  ReadingHistoryUiState copyWith({
    List<ReadingHistoryEntry>? entries,
    bool? loading,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) => ReadingHistoryUiState(
    entries: entries ?? this.entries,
    loading: loading ?? this.loading,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : error ?? this.error,
  );
}

class ReadingHistoryViewModel extends Notifier<ReadingHistoryUiState> {
  late final ReadingHistoryRepository _repository;
  StreamSubscription<int>? _subscription;
  int _loadEpoch = 0;
  bool _active = true;

  @override
  ReadingHistoryUiState build() {
    _active = true;
    _repository = ref.read(readingHistoryRepositoryProvider);
    ref.onDispose(() {
      _active = false;
      _loadEpoch++;
      unawaited(_subscription?.cancel());
    });
    unawaited(Future<void>.microtask(_start));
    return const ReadingHistoryUiState();
  }

  Future<void> _start() async {
    if (!_active) return;
    _subscription = _repository.changes.listen((_) => unawaited(reload()));
    await reload();
  }

  Future<void> reload() async {
    _loadEpoch++;
    state = state.copyWith(hasMore: true);
    await _load(reset: true);
  }

  Future<void> loadMore() => _load();

  Future<bool> delete(String url) async {
    try {
      await _repository.delete(url);
      return _active;
    } on Object {
      return false;
    }
  }

  Future<bool> clear() async {
    try {
      await _repository.clear();
      return _active;
    } on Object {
      return false;
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (!_active || (state.loading && !reset) || !state.hasMore) return;
    final int epoch = _loadEpoch;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final List<ReadingHistoryEntry> rows = await _repository.page(
        offset: reset ? 0 : state.entries.length,
      );
      if (!_active || epoch != _loadEpoch) return;
      state = state.copyWith(
        entries: List<ReadingHistoryEntry>.unmodifiable(<ReadingHistoryEntry>[
          if (!reset) ...state.entries,
          ...rows,
        ]),
        hasMore: rows.length == 20,
        loading: false,
        clearError: true,
      );
    } on Object catch (error) {
      if (!_active || epoch != _loadEpoch) return;
      state = state.copyWith(loading: false, error: error);
    }
  }
}
