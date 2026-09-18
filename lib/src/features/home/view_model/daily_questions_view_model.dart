import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_controller.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_state.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

final NotifierProvider<DailyQuestionsViewModel, PagedState<Article>>
dailyQuestionsViewModelProvider =
    NotifierProvider<DailyQuestionsViewModel, PagedState<Article>>(
      DailyQuestionsViewModel.new,
      dependencies: [homeChildRouteInstanceProvider],
      isAutoDispose: true,
    );

class DailyQuestionsViewModel extends Notifier<PagedState<Article>> {
  late final PagingController<Article, void> _paging;
  StreamSubscription<PagingSnapshot<Article, void>>? _subscription;

  @override
  PagedState<Article> build() {
    ref.watch(homeChildRouteInstanceProvider);
    _paging = PagingController<Article, void>(
      initialPage: 1,
      keyOf: (Article article) => article.id,
      initialContext: null,
      requestPage: (void _, int page, RequestCancellation cancellation) =>
          ref.read(articleRepositoryProvider).questionPage(page, cancellation),
    );
    _subscription = _paging.changes.listen((
      PagingSnapshot<Article, void> snapshot,
    ) {
      state = snapshot.page;
    });
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      unawaited(_paging.dispose());
    });
    unawaited(Future<void>.microtask(_paging.startInitialLoad));
    return const PagedState<Article>(initial: LoadLoading());
  }

  Future<void> refresh() => _paging.refresh();
  Future<void> retryInitial() => _paging.retryInitial();
  Future<void> retryRefresh() => _paging.retryRefresh();
  Future<void> loadMore() => _paging.loadMore();
  Future<void> retryLoadMore() => _paging.retryAppend();
  Future<void> continueAfterPause() => _paging.continueAfterPause();
}
