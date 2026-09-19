import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/platform/app_visibility.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/topic_repository.dart';
import 'package:wanandroid_flutter/src/features/topics/state/topics_ui_state.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_dependencies.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_view_model.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';
import 'package:wanandroid_flutter/src/model/topic.dart';

void main() {
  test(
    'selects first real child and keeps equal names separate by ID',
    () async {
      final _TopicFixture repository = _TopicFixture();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await _flush();

      expect(container.read(topicsViewModelProvider).selectedId, 11);
      expect(repository.requests.single.categoryId, 11);
      expect(repository.requests.single.page, 0);
      repository.requests.single.succeed(<Article>[
        _article(11),
      ], nextPage: null);
      await _flush();
      container.read(topicsViewModelProvider.notifier).selectChild(10, 12);
      await _flush();
      expect(container.read(topicsViewModelProvider).selectedId, 12);
      expect(repository.requests.last.categoryId, 12);
      expect(container.read(topicsViewModelProvider).tabs.length, 2);
      expect(container.read(topicsViewModelProvider).tabs[0].name, '同名');
      expect(container.read(topicsViewModelProvider).tabs[1].name, '同名');
    },
  );

  test(
    'switch cancels append, ignores late result and resumes same cursor',
    () async {
      final _TopicFixture repository = _TopicFixture();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await _flush();
      repository.requests.removeAt(0).succeed(<Article>[
        _article(11),
      ], nextPage: 1);
      await _flush();

      final TopicsViewModel model = container.read(
        topicsViewModelProvider.notifier,
      );
      unawaited(model.loadMore(11));
      await _flush();
      final _PageRequest old = repository.requests.removeAt(0);
      model.selectChild(10, 12);
      await _flush();
      expect(old.cancellation.isCancelled, isTrue);
      repository.requests.removeAt(0).succeed(<Article>[
        _article(12),
      ], nextPage: null);
      await _flush();
      old.succeed(<Article>[_article(99)], nextPage: null);
      await _flush();
      expect(
        container.read(topicsViewModelProvider).selectedPage.items.single.id,
        12,
      );

      model.selectChild(10, 11);
      await _flush();
      expect(
        container.read(topicsViewModelProvider).selectedPage.items.single.id,
        11,
      );
      expect(repository.requests.single.categoryId, 11);
      expect(repository.requests.single.page, 1);
      repository.requests.single.succeed(<Article>[
        _article(13),
      ], nextPage: null);
      await _flush();
      expect(
        container
            .read(topicsViewModelProvider)
            .selectedPage
            .items
            .map((Article item) => item.id),
        <int>[11, 13],
      );
    },
  );

  test(
    'parent selection restores last child and rejects old callbacks',
    () async {
      final _TopicFixture repository = _TopicFixture();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await _flush();
      repository.requests.removeAt(0).succeed(<Article>[
        _article(11),
      ], nextPage: null);
      await _flush();
      final TopicsViewModel model = container.read(
        topicsViewModelProvider.notifier,
      );
      model.selectChild(10, 12);
      await _flush();
      final _PageRequest child = repository.requests.removeAt(0);
      model.selectParent(20);
      await _flush();
      expect(child.cancellation.isCancelled, isTrue);
      model.selectChild(10, 11);
      unawaited(model.refresh(12));
      expect(repository.requests.single.categoryId, 21);
      repository.requests.removeAt(0).succeed(<Article>[
        _article(21),
      ], nextPage: null);
      child.succeed(<Article>[_article(99)], nextPage: null);
      await _flush();
      model.selectParent(10);
      await _flush();
      expect(container.read(topicsViewModelProvider).selectedId, 12);
      expect(repository.requests.single.categoryId, 12);
    },
  );

  test(
    'category error retries; empty child list makes no article request',
    () async {
      final _TopicFixture repository = _TopicFixture()
        ..tree = const DataFailure<List<Topic>>(DataError.network);
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await _flush();
      expect(container.read(topicsViewModelProvider).error, DataError.network);
      expect(repository.requests, isEmpty);

      repository.tree = const DataSuccess<List<Topic>>(<Topic>[
        Topic(id: 10, name: '空分类'),
      ]);
      await container.read(topicsViewModelProvider.notifier).retryTopics();
      final TopicsUiState state = container.read(topicsViewModelProvider);
      expect(state.loading, isFalse);
      expect(state.error, isNull);
      expect(state.selectedParentId, 10);
      expect(state.selectedId, isNull);
      expect(repository.requests, isEmpty);
    },
  );

  test('background cancels and foreground resumes selected category', () async {
    final _TopicFixture repository = _TopicFixture();
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    await _flush();
    final _PageRequest old = repository.requests.removeAt(0);
    container
        .read(appVisibilityProvider.notifier)
        .updateLifecycle(AppLifecycleState.paused);
    await _flush();
    expect(old.cancellation.isCancelled, isTrue);
    container
        .read(appVisibilityProvider.notifier)
        .updateLifecycle(AppLifecycleState.resumed);
    await _flush();
    expect(repository.requests.single.categoryId, 11);
    expect(repository.requests.single.page, 0);
    repository.requests.single.succeed(<Article>[_article(11)], nextPage: null);
    await _flush();
    expect(
      container.read(topicsViewModelProvider).selectedPage.items.single.id,
      11,
    );
  });

  test('article failure retries and an empty category remains empty', () async {
    final _TopicFixture repository = _TopicFixture();
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    await _flush();
    repository.requests.removeAt(0).fail(DataError.network);
    await _flush();
    expect(
      container.read(topicsViewModelProvider).selectedPage.initialError,
      DataError.network,
    );

    unawaited(
      container.read(topicsViewModelProvider.notifier).retryInitial(11),
    );
    await _flush();
    expect(repository.requests.single.page, 0);
    repository.requests.removeAt(0).succeed(<Article>[], nextPage: null);
    await _flush();
    final TopicsUiState state = container.read(topicsViewModelProvider);
    expect(state.selectedPage.items, isEmpty);
    expect(state.selectedPage.initialError, isNull);
    expect(state.selectedPage.canLoadMore, isFalse);
  });

  test(
    'inactive category controllers are bounded by the cache limit',
    () async {
      final _TopicFixture repository = _TopicFixture()
        ..tree = DataSuccess<List<Topic>>(<Topic>[
          const Topic(id: 10, name: '分类'),
          for (int id = 11; id <= 20; id++)
            Topic(id: id, name: '分类 $id', parentId: 10),
        ]);
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await _flush();
      final TopicsViewModel model = container.read(
        topicsViewModelProvider.notifier,
      );
      for (int id = 11; id <= 20; id++) {
        if (id != 11) {
          model.selectChild(10, id);
          await _flush();
        }
        repository.requests.removeAt(0).succeed(<Article>[
          _article(id),
        ], nextPage: null);
        await _flush();
      }
      expect(
        container.read(topicsViewModelProvider).pageStates.length,
        lessThanOrEqualTo(8),
      );
      model.selectChild(10, 11);
      await _flush();
      expect(repository.requests.single.categoryId, 11);
      expect(repository.requests.single.page, 0);
    },
  );
}

ProviderContainer _container(_TopicFixture repository) {
  final ProviderContainer container = ProviderContainer(
    overrides: [topicRepositoryProvider.overrideWithValue(repository)],
  );
  container
      .read(appVisibilityProvider.notifier)
      .updateRoute(
        activeBranch: 1,
        homeRouteCurrent: false,
        topicsRouteCurrent: true,
      );
  container.listen<TopicsUiState>(topicsViewModelProvider, (_, _) {});
  return container;
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _PageRequest {
  _PageRequest(this.categoryId, this.page, this.cancellation);

  final int categoryId;
  final int page;
  final RequestCancellation cancellation;
  final Completer<DataResult<PageResult<Article>>> _result =
      Completer<DataResult<PageResult<Article>>>();

  Future<DataResult<PageResult<Article>>> get future => _result.future;

  void succeed(List<Article> items, {required int? nextPage}) =>
      _result.complete(
        DataSuccess<PageResult<Article>>(
          PageResult<Article>(items: items, nextPage: nextPage),
        ),
      );

  void fail(DataError error) =>
      _result.complete(DataFailure<PageResult<Article>>(error));
}

class _TopicFixture implements TopicRepository {
  DataResult<List<Topic>> tree = const DataSuccess<List<Topic>>(<Topic>[
    Topic(id: 10, name: '开发语言'),
    Topic(id: 11, name: '同名', parentId: 10),
    Topic(id: 12, name: '同名', parentId: 10),
    Topic(id: 20, name: '移动开发'),
    Topic(id: 21, name: 'Android', parentId: 20),
  ]);
  final List<_PageRequest> requests = <_PageRequest>[];

  @override
  Future<DataResult<List<Topic>>> topics(
    RequestCancellation cancellation,
  ) async => tree;

  @override
  Future<DataResult<PageResult<Article>>> articles(
    int categoryId,
    int page,
    RequestCancellation cancellation,
  ) {
    final _PageRequest request = _PageRequest(categoryId, page, cancellation);
    requests.add(request);
    return request.future;
  }
}

Article _article(int id) => Article(
  id: id,
  title: '文章 $id',
  url: 'https://fixture.invalid/article/$id',
  author: '固定作者',
  shareUser: '',
  superChapterName: '专题',
  chapter: '分类',
  publishedAt: '2026-09-19',
  collected: false,
);
