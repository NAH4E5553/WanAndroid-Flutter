import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/collection_repository.dart';
import 'package:wanandroid_flutter/src/model/collection.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

final NotifierProvider<CollectionsViewModel, CollectionsUiState>
collectionsViewModelProvider =
    NotifierProvider.autoDispose<CollectionsViewModel, CollectionsUiState>(
      CollectionsViewModel.new,
    );

class CollectionsUiState {
  const CollectionsUiState({
    this.items = const <CollectionItem>[],
    this.generation,
    this.nextPage,
    this.loading = false,
    this.appending = false,
    this.error,
    this.busyKeys = const <String>{},
  });

  final List<CollectionItem> items;
  final int? generation;
  final int? nextPage;
  final bool loading;
  final bool appending;
  final DataError? error;
  final Set<String> busyKeys;

  CollectionsUiState copyWith({
    List<CollectionItem>? items,
    int? generation,
    bool clearGeneration = false,
    int? nextPage,
    bool clearNextPage = false,
    bool? loading,
    bool? appending,
    DataError? error,
    bool clearError = false,
    Set<String>? busyKeys,
  }) => CollectionsUiState(
    items: items ?? this.items,
    generation: clearGeneration ? null : generation ?? this.generation,
    nextPage: clearNextPage ? null : nextPage ?? this.nextPage,
    loading: loading ?? this.loading,
    appending: appending ?? this.appending,
    error: clearError ? null : error ?? this.error,
    busyKeys: busyKeys ?? this.busyKeys,
  );
}

class CollectionsViewModel extends Notifier<CollectionsUiState> {
  static const int _firstPage = 0;

  late final CollectionRepository _repository;
  bool _active = true;

  @override
  CollectionsUiState build() {
    _active = true;
    _repository = ref.read(collectionRepositoryProvider);
    _repository.addListener(_onCollectionChanged);
    ref.onDispose(() {
      _active = false;
      _repository.removeListener(_onCollectionChanged);
    });
    final int? generation = _repository.current.generation;
    unawaited(Future<void>.microtask(refresh));
    return CollectionsUiState(
      generation: generation,
      loading: generation != null,
      busyKeys: _busyKeys(_repository.current),
    );
  }

  Future<void> refresh() async {
    final int? generation = _repository.current.generation;
    if (generation == null) {
      state = CollectionsUiState(busyKeys: _busyKeys(_repository.current));
      return;
    }
    state = state.copyWith(
      generation: generation,
      loading: true,
      clearError: true,
    );
    final DataResult<PageResult<CollectionItem>> result = await _repository
        .page(generation, _firstPage);
    if (!_active || generation != state.generation) return;
    state = switch (result) {
      DataSuccess<PageResult<CollectionItem>>(:final value) => state.copyWith(
        items: List<CollectionItem>.unmodifiable(value.items),
        nextPage: value.nextPage,
        clearNextPage: value.nextPage == null,
        loading: false,
        clearError: true,
      ),
      DataFailure<PageResult<CollectionItem>>(:final error) => state.copyWith(
        loading: false,
        error: error,
      ),
    };
  }

  Future<void> loadMore() async {
    final int? generation = state.generation;
    final int? nextPage = state.nextPage;
    if (generation == null || nextPage == null || state.appending) return;
    state = state.copyWith(appending: true);
    final DataResult<PageResult<CollectionItem>> result = await _repository
        .page(generation, nextPage);
    if (!_active || generation != state.generation) return;
    state = switch (result) {
      DataSuccess<PageResult<CollectionItem>>(:final value) => state.copyWith(
        items: List<CollectionItem>.unmodifiable(<CollectionItem>[
          ...state.items,
          ...value.items,
        ]),
        nextPage: value.nextPage,
        clearNextPage: value.nextPage == null,
        appending: false,
      ),
      DataFailure<PageResult<CollectionItem>>() => state.copyWith(
        appending: false,
      ),
    };
  }

  Future<bool> remove(CollectionItem item) async {
    final int? generation = _repository.current.generation;
    if (generation == null) return false;
    final DataResult<void> result = await _repository.setCollected(
      generation,
      item.target,
      false,
    );
    if (!_active) return false;
    if (result is DataSuccess<void>) {
      state = state.copyWith(
        items: List<CollectionItem>.unmodifiable(
          state.items.where(
            (CollectionItem current) => current.target.key != item.target.key,
          ),
        ),
      );
      return true;
    }
    return false;
  }

  void _onCollectionChanged() {
    if (!_active) return;
    final CollectionSnapshot snapshot = _repository.current;
    final int? generation = snapshot.generation;
    if (generation == null) {
      state = CollectionsUiState(busyKeys: _busyKeys(snapshot));
      return;
    }
    if (generation != state.generation) {
      state = CollectionsUiState(
        generation: generation,
        loading: true,
        busyKeys: _busyKeys(snapshot),
      );
      unawaited(refresh());
      return;
    }
    state = state.copyWith(busyKeys: _busyKeys(snapshot));
  }

  Set<String> _busyKeys(CollectionSnapshot snapshot) =>
      Set<String>.unmodifiable(
        snapshot.statuses.entries
            .where(
              (MapEntry<String, CollectionStatus> entry) => entry.value.busy,
            )
            .map((MapEntry<String, CollectionStatus> entry) => entry.key),
      );
}
