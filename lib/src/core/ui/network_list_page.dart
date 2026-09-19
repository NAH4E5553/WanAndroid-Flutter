import 'package:flutter/material.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_state.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';

class NetworkListPage<T> extends StatelessWidget {
  const NetworkListPage({
    required this.state,
    required this.itemBuilder,
    required this.onRefresh,
    required this.onRetryInitial,
    required this.onLoadMore,
    required this.onRetryLoadMore,
    required this.onContinue,
    this.emptyLabel = '暂无内容',
    this.scrollKey,
    this.pagingEnabled = true,
    this.onRetryRefresh,
    super.key,
  });

  final PagedState<T> state;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final RefreshCallback onRefresh;
  final VoidCallback onRetryInitial;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryLoadMore;
  final VoidCallback onContinue;
  final String emptyLabel;
  final Key? scrollKey;
  final bool pagingEnabled;
  final VoidCallback? onRetryRefresh;

  @override
  Widget build(BuildContext context) {
    if (state.items.isEmpty && state.isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.items.isEmpty && state.initialError != null) {
      return _NetworkError(error: state.initialError!, onRetry: onRetryInitial);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (pagingEnabled && notification.metrics.extentAfter < 480) {
          onLoadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.builder(
          key: scrollKey,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: state.items.isEmpty
              ? 1
              : state.items.length +
                    1 +
                    (state.refreshError != null && onRetryRefresh != null
                        ? 1
                        : 0),
          itemBuilder: (BuildContext context, int index) {
            if (state.items.isEmpty) {
              return SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.6,
                child: Center(child: Text(emptyLabel)),
              );
            }
            final bool showRefreshError =
                state.refreshError != null && onRetryRefresh != null;
            if (showRefreshError && index == 0) {
              return Center(
                child: TextButton(
                  onPressed: onRetryRefresh,
                  child: const Text('刷新失败，点击重试'),
                ),
              );
            }
            final int itemIndex = index - (showRefreshError ? 1 : 0);
            if (itemIndex < state.items.length) {
              return itemBuilder(context, state.items[itemIndex], itemIndex);
            }
            return _LoadMoreFooter(
              state: state,
              onRetry: onRetryLoadMore,
              onContinue: onContinue,
            );
          },
        ),
      ),
    );
  }
}

class _NetworkError extends StatelessWidget {
  const _NetworkError({required this.error, required this.onRetry});

  final DataError error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(context.spacing.section),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: context.spacing.medium,
        children: <Widget>[
          Text(_errorLabel(error), textAlign: TextAlign.center),
          FilledButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}

class _LoadMoreFooter<T> extends StatelessWidget {
  const _LoadMoreFooter({
    required this.state,
    required this.onRetry,
    required this.onContinue,
  });

  final PagedState<T> state;
  final VoidCallback onRetry;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.loadMoreError != null) {
      return Center(
        child: TextButton(onPressed: onRetry, child: const Text('加载失败，点击重试')),
      );
    }
    if (state.autoLoadPaused) {
      return Center(
        child: TextButton(onPressed: onContinue, child: const Text('继续加载')),
      );
    }
    if (!state.canLoadMore) {
      return Padding(
        padding: EdgeInsets.all(context.spacing.section),
        child: const Center(child: Text('已经到底了')),
      );
    }
    return const SizedBox(height: 48);
  }
}

String _errorLabel(DataError error) => switch (error) {
  DataError.network => '网络连接失败，请稍后重试',
  DataError.service => '服务暂时不可用，请稍后重试',
  DataError.sessionExpired => '登录状态已失效',
  DataError.sessionChanged => '账号状态已变化，请重试',
  DataError.invalidResponse => '数据格式异常，请稍后重试',
  DataError.storage => '本地数据读取失败',
};
