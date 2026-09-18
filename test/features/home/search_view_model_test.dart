import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/search_suggestions_repository.dart';
import 'package:wanandroid_flutter/src/features/home/state/search_ui_state.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/search_view_model.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';
import 'package:wanandroid_flutter/src/model/search_history.dart';

void main() {
  test('new query cancels and isolates the older result', () async {
    final _SearchArticleRepository articles = _SearchArticleRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        articleRepositoryProvider.overrideWithValue(articles),
        searchSuggestionsRepositoryProvider.overrideWithValue(
          _SearchSuggestionsRepository(),
        ),
        homeChildRouteInstanceProvider.overrideWithValue('search-1'),
      ],
    );
    addTearDown(container.dispose);
    final ProviderSubscription<SearchUiState> subscription = container.listen(
      searchViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final SearchViewModel viewModel = container.read(
      searchViewModelProvider.notifier,
    );
    await _flush();

    viewModel.editInput('甲');
    await viewModel.submit();
    final _SearchRequest first = articles.requests.removeFirst();
    viewModel.editInput('乙');
    await viewModel.submit();
    final _SearchRequest second = articles.requests.removeFirst();
    expect(first.cancellation.isCancelled, isTrue);

    second.complete(_article(2, '乙结果'));
    await _flush();
    first.complete(_article(1, '甲迟到结果'));
    await _flush();

    final SearchUiState state = container.read(searchViewModelProvider);
    expect(state.keyword, '乙');
    expect(state.page.items.single.title, '乙结果');
    expect(state.showResults, isTrue);

    viewModel.editInput('正在编辑');
    expect(container.read(searchViewModelProvider).showResults, isFalse);
  });

  test('blank query does not issue a request', () async {
    final _SearchArticleRepository articles = _SearchArticleRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        articleRepositoryProvider.overrideWithValue(articles),
        searchSuggestionsRepositoryProvider.overrideWithValue(
          _SearchSuggestionsRepository(),
        ),
        homeChildRouteInstanceProvider.overrideWithValue('search-2'),
      ],
    );
    addTearDown(container.dispose);
    final ProviderSubscription<SearchUiState> subscription = container.listen(
      searchViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final SearchViewModel viewModel = container.read(
      searchViewModelProvider.notifier,
    );

    viewModel.editInput('   ');
    await viewModel.submit();

    expect(articles.requests, isEmpty);
  });
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Article _article(int id, String title) => Article(
  id: id,
  title: title,
  url: 'https://fixture.invalid/$id',
  author: '作者',
  shareUser: '',
  superChapterName: '搜索',
  chapter: 'Flutter',
  publishedAt: '2026-09-18',
  collected: false,
);

class _SearchRequest {
  _SearchRequest(this.keyword, this.cancellation);

  final String keyword;
  final RequestCancellation cancellation;
  final Completer<DataResult<PageResult<Article>>> completer =
      Completer<DataResult<PageResult<Article>>>();

  void complete(Article article) {
    if (!completer.isCompleted) {
      completer.complete(
        DataSuccess<PageResult<Article>>(
          PageResult<Article>(items: <Article>[article], nextPage: null),
        ),
      );
    }
  }
}

class _SearchArticleRepository implements ArticleRepository {
  final ListQueue<_SearchRequest> requests = ListQueue<_SearchRequest>();

  @override
  Future<DataResult<PageResult<Article>>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) {
    final _SearchRequest request = _SearchRequest(keyword, cancellation);
    requests.add(request);
    return request.completer.future;
  }

  @override
  Future<DataResult<PageResult<Article>>> articles(
    int page,
    RequestCancellation cancellation,
  ) => throw UnimplementedError();

  @override
  Future<DataResult<PageResult<Article>>> questionPage(
    int page,
    RequestCancellation cancellation,
  ) => throw UnimplementedError();

  @override
  Future<DataResult<List<Article>>> questions(
    RequestCancellation cancellation,
  ) => throw UnimplementedError();
}

class _SearchSuggestionsRepository implements SearchSuggestionsRepository {
  @override
  Future<bool> clearHistory() async => true;

  @override
  Future<DataResult<List<String>>> hotKeys(
    RequestCancellation cancellation,
  ) async => const DataSuccess<List<String>>(<String>['Flutter']);

  @override
  Future<SearchHistory> loadHistory() async => const SearchHistory(ready: true);

  @override
  Future<bool> record(String keyword) async => true;
}
