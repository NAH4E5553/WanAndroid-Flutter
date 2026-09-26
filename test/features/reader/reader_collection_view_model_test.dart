import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/collection_repository.dart';
import 'package:wanandroid_flutter/src/features/reader/view_model/reader_collection_view_model.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/collection.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

void main() {
  test(
    'reader collection view model derives state and expresses target',
    () async {
      final _CollectionFixture repository = _CollectionFixture();
      final ReaderCollectionViewModel viewModel = ReaderCollectionViewModel(
        repository,
      );

      final ReaderCollectUiState state = viewModel.state(7);
      expect(state.authenticated, isTrue);
      expect(state.collected, isTrue);
      expect(state.busy, isFalse);

      expect(await viewModel.toggle(7), isTrue);
      expect(repository.lastGeneration, 4);
      expect(repository.lastTarget, const CollectionTarget(7, null));
      expect(repository.lastCollected, isFalse);
    },
  );

  test(
    'reader collection view model rejects guest and external targets',
    () async {
      final _CollectionFixture repository = _CollectionFixture(
        snapshot: const CollectionSnapshot(),
      );
      final ReaderCollectionViewModel viewModel = ReaderCollectionViewModel(
        repository,
      );

      expect(viewModel.state(7).authenticated, isFalse);
      expect(await viewModel.toggle(7), isFalse);
      expect(await viewModel.toggle(null), isFalse);
      expect(repository.lastTarget, isNull);
    },
  );

  test('reader collection view model contains repository failures', () async {
    final ReaderCollectionViewModel viewModel = ReaderCollectionViewModel(
      _CollectionFixture(throwOnWrite: true),
    );

    expect(await viewModel.toggle(7), isFalse);
  });
}

final class _CollectionFixture implements CollectionRepository {
  _CollectionFixture({
    this.snapshot = const CollectionSnapshot(
      generation: 4,
      sessionKey: 'fixture:4',
      statuses: <String, CollectionStatus>{
        'article:7|record:null': CollectionStatus(collected: true),
      },
    ),
    this.throwOnWrite = false,
  });

  final CollectionSnapshot snapshot;
  final bool throwOnWrite;
  int? lastGeneration;
  CollectionTarget? lastTarget;
  bool? lastCollected;

  @override
  CollectionSnapshot get current => snapshot;

  @override
  void addListener(void Function() listener) {}

  @override
  void removeListener(void Function() listener) {}

  @override
  Future<DataResult<PageResult<Article>>> articlePage(
    Future<DataResult<PageResult<Article>>> Function() load,
  ) => load();

  @override
  Future<DataResult<PageResult<CollectionItem>>> page(
    int generation,
    int page,
  ) async =>
      const DataFailure<PageResult<CollectionItem>>(DataError.invalidResponse);

  @override
  Future<DataResult<void>> reconcile(
    int generation,
    CollectionTarget target,
  ) async => const DataSuccess<void>(null);

  @override
  Future<DataResult<void>> setCollected(
    int generation,
    CollectionTarget target,
    bool collected,
  ) async {
    if (throwOnWrite) throw StateError('fixture write failure');
    lastGeneration = generation;
    lastTarget = target;
    lastCollected = collected;
    return const DataSuccess<void>(null);
  }
}
