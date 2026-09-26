import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/collection_repository.dart';
import 'package:wanandroid_flutter/src/model/collection.dart';

/// Null outside the production composition root keeps isolated stage-4 reader
/// fixtures independent from stage-5 account and collection wiring.
final Provider<ReaderCollectionViewModel?> readerCollectionViewModelProvider =
    Provider<ReaderCollectionViewModel?>((Ref ref) => null);

class ReaderCollectionViewModel {
  const ReaderCollectionViewModel(this._repository);

  final CollectionRepository _repository;

  ReaderCollectUiState state(int? articleId) {
    final CollectionSnapshot snapshot = _repository.current;
    final int? generation = snapshot.generation;
    if (generation == null || articleId == null) {
      return const ReaderCollectUiState();
    }
    final CollectionStatus status = snapshot.status(
      CollectionTarget(articleId, null),
    );
    return ReaderCollectUiState(
      authenticated: true,
      collected: status.collected,
      busy: status.busy,
    );
  }

  Future<bool> toggle(int? articleId) async {
    final CollectionSnapshot snapshot = _repository.current;
    final int? generation = snapshot.generation;
    if (generation == null || articleId == null) return false;
    final CollectionTarget target = CollectionTarget(articleId, null);
    final CollectionStatus status = snapshot.status(target);
    if (status.busy) return false;
    try {
      final DataResult<void> result = await _repository.setCollected(
        generation,
        target,
        !(status.collected ?? false),
      );
      return result is DataSuccess<void>;
    } on Object {
      return false;
    }
  }
}

class ReaderCollectUiState {
  const ReaderCollectUiState({
    this.authenticated = false,
    this.collected,
    this.busy = false,
  });

  final bool authenticated;
  final bool? collected;
  final bool busy;
}
