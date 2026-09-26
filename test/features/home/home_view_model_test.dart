import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/platform/app_visibility.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/features/home/state/home_ui_state.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_view_model.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

void main() {
  test('loads article page and questions independently', () async {
    final _FakeArticleRepository repository = _FakeArticleRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: [articleRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final ProviderSubscription<HomeUiState> subscription = container.listen(
      homeViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await _flush();

    final HomeUiState state = container.read(homeViewModelProvider);
    expect(state.articles.items.single.id, 101);
    expect(state.questions.items.single.id, 201);
    expect(repository.articlePages, <int>[0]);
    expect(repository.questionRequests, 1);
  });

  test('refresh replaces both resources through the same repository', () async {
    final _FakeArticleRepository repository = _FakeArticleRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: [articleRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final ProviderSubscription<HomeUiState> subscription = container.listen(
      homeViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await _flush();

    await container.read(homeViewModelProvider.notifier).refresh();

    expect(repository.articlePages, <int>[0, 0]);
    expect(repository.questionRequests, 2);
    expect(container.read(homeViewModelProvider).articles.items.single.id, 101);
  });

  test(
    'background cancels active home reads and foreground resumes them',
    () async {
      final _ControlledArticleRepository repository =
          _ControlledArticleRepository();
      final ProviderContainer container = ProviderContainer(
        overrides: [articleRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final ProviderSubscription<HomeUiState> subscription = container.listen(
        homeViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await _flush();

      expect(repository.articleRequests.length, 1);
      expect(repository.questionRequests.length, 1);
      container
          .read(appVisibilityProvider.notifier)
          .updateLifecycle(AppLifecycleState.paused);
      await _flush();
      expect(container.read(homeViewModelProvider).visible, isFalse);
      expect(repository.articleRequests.first.cancellation.isCancelled, isTrue);
      expect(
        repository.questionRequests.first.cancellation.isCancelled,
        isTrue,
      );

      container
          .read(appVisibilityProvider.notifier)
          .updateLifecycle(AppLifecycleState.resumed);
      await _flush();
      expect(container.read(homeViewModelProvider).visible, isTrue);
      expect(repository.articleRequests.length, 2);
      expect(repository.questionRequests.length, 2);
      repository.articleRequests.last.complete(
        DataSuccess<PageResult<Article>>(
          const PageResult<Article>(items: <Article>[_article], nextPage: null),
        ),
      );
      repository.questionRequests.last.complete(
        const DataSuccess<List<Article>>(<Article>[_question]),
      );
      await _flush();
      expect(container.read(homeViewModelProvider).articles.items, <Article>[
        _article,
      ]);
    },
  );
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeArticleRepository implements ArticleRepository {
  final List<int> articlePages = <int>[];
  int questionRequests = 0;

  @override
  Future<DataResult<PageResult<Article>>> articles(
    int page,
    RequestCancellation cancellation,
  ) async {
    articlePages.add(page);
    cancellation.throwIfCancelled();
    return DataSuccess<PageResult<Article>>(
      PageResult<Article>(items: const <Article>[_article], nextPage: null),
    );
  }

  @override
  Future<DataResult<List<Article>>> questions(
    RequestCancellation cancellation,
  ) async {
    questionRequests += 1;
    cancellation.throwIfCancelled();
    return const DataSuccess<List<Article>>(<Article>[_question]);
  }

  @override
  Future<DataResult<PageResult<Article>>> questionPage(
    int page,
    RequestCancellation cancellation,
  ) => throw UnimplementedError();

  @override
  Future<DataResult<PageResult<Article>>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) => throw UnimplementedError();
}

class _Pending<T> {
  _Pending(this.cancellation);

  final RequestCancellation cancellation;
  final Completer<DataResult<T>> _completer = Completer<DataResult<T>>();

  Future<DataResult<T>> get future => _completer.future;

  void complete(DataResult<T> result) => _completer.complete(result);
}

class _ControlledArticleRepository implements ArticleRepository {
  final List<_Pending<PageResult<Article>>> articleRequests =
      <_Pending<PageResult<Article>>>[];
  final List<_Pending<List<Article>>> questionRequests =
      <_Pending<List<Article>>>[];

  @override
  Future<DataResult<PageResult<Article>>> articles(
    int page,
    RequestCancellation cancellation,
  ) {
    final _Pending<PageResult<Article>> request = _Pending<PageResult<Article>>(
      cancellation,
    );
    articleRequests.add(request);
    return request.future;
  }

  @override
  Future<DataResult<List<Article>>> questions(
    RequestCancellation cancellation,
  ) {
    final _Pending<List<Article>> request = _Pending<List<Article>>(
      cancellation,
    );
    questionRequests.add(request);
    return request.future;
  }

  @override
  Future<DataResult<PageResult<Article>>> questionPage(
    int page,
    RequestCancellation cancellation,
  ) => throw UnimplementedError();

  @override
  Future<DataResult<PageResult<Article>>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) => throw UnimplementedError();
}

const Article _article = Article(
  id: 101,
  title: 'Article',
  url: 'https://fixture.invalid/a',
  author: 'Author',
  shareUser: '',
  superChapterName: 'A',
  chapter: 'Flutter',
  publishedAt: '2026-09-18',
  collected: false,
);

const Article _question = Article(
  id: 201,
  title: 'Question',
  url: 'https://fixture.invalid/q',
  author: 'Author',
  shareUser: '',
  superChapterName: 'Q',
  chapter: 'Flutter',
  publishedAt: '2026-09-18',
  collected: false,
);
