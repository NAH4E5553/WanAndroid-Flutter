import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/collection_repository.dart';
import 'package:wanandroid_flutter/src/features/profile/view_model/collections_view_model.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/collection.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

void main() {
  test('collections view model owns paging and removal', () async {
    final _CollectionFixture repository = _CollectionFixture();
    final ProviderContainer container = ProviderContainer(
      overrides: [collectionRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final ProviderSubscription<CollectionsUiState> subscription = container
        .listen(collectionsViewModelProvider, (_, _) {}, fireImmediately: true);
    addTearDown(subscription.close);

    await pumpEventQueue();
    expect(
      subscription.read().items.single.target,
      const CollectionTarget(7, 9),
    );
    expect(repository.pages, <int>[0]);

    final bool removed = await container
        .read(collectionsViewModelProvider.notifier)
        .remove(subscription.read().items.single);
    expect(removed, isTrue);
    expect(subscription.read().items, isEmpty);
  });

  test(
    'repository invalidation removes an item without a list reload',
    () async {
      final _CollectionFixture repository = _CollectionFixture();
      final ProviderContainer container = ProviderContainer(
        overrides: [collectionRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final ProviderSubscription<CollectionsUiState> subscription = container
          .listen(
            collectionsViewModelProvider,
            (_, _) {},
            fireImmediately: true,
          );
      addTearDown(subscription.close);

      await pumpEventQueue();
      expect(subscription.read().items, hasLength(1));

      repository.publishReaderUncollect();

      expect(subscription.read().items, isEmpty);
      expect(repository.pages, <int>[0]);
    },
  );
}

final class _CollectionFixture extends ChangeNotifier
    implements CollectionRepository {
  final List<int> pages = <int>[];
  CollectionSnapshot _snapshot = const CollectionSnapshot(
    generation: 1,
    sessionKey: 'fixture:1',
    statuses: <String, CollectionStatus>{
      'article:7|record:null': CollectionStatus(collected: true),
      'article:7|record:9': CollectionStatus(collected: true),
    },
  );

  @override
  CollectionSnapshot get current => _snapshot;

  void publishReaderUncollect() {
    _snapshot = _snapshot.copyWith(
      revision: _snapshot.revision + 1,
      statuses: const <String, CollectionStatus>{
        'article:7|record:null': CollectionStatus(collected: false),
        'article:7|record:9': CollectionStatus(collected: false),
      },
    );
    notifyListeners();
  }

  @override
  Future<DataResult<PageResult<Article>>> articlePage(
    Future<DataResult<PageResult<Article>>> Function() load,
  ) => load();

  @override
  Future<DataResult<PageResult<CollectionItem>>> page(
    int generation,
    int page,
  ) async {
    pages.add(page);
    return const DataSuccess<PageResult<CollectionItem>>(
      PageResult<CollectionItem>(
        items: <CollectionItem>[_item],
        nextPage: null,
      ),
    );
  }

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
  ) async => const DataSuccess<void>(null);
}

const CollectionItem _item = CollectionItem(
  target: CollectionTarget(7, 9),
  article: Article(
    id: 7,
    title: '固定收藏',
    url: 'https://example.test/7',
    author: '作者',
    shareUser: '',
    superChapterName: '软件',
    chapter: '开发',
    publishedAt: '2026-09-26',
    collected: true,
  ),
);
