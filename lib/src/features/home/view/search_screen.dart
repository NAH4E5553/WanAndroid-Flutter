import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/core/ui/app_scaffold.dart';
import 'package:wanandroid_flutter/src/core/ui/app_top_bar.dart';
import 'package:wanandroid_flutter/src/core/ui/article_card.dart';
import 'package:wanandroid_flutter/src/core/ui/network_list_page.dart';
import 'package:wanandroid_flutter/src/features/home/state/search_ui_state.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/search_view_model.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({
    required this.onBack,
    required this.onArticleTap,
    super.key,
  });

  final VoidCallback onBack;
  final ValueChanged<Article> onArticleTap;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SearchUiState state = ref.watch(searchViewModelProvider);
    final SearchViewModel viewModel = ref.read(
      searchViewModelProvider.notifier,
    );
    return AppScaffold(
      topBar: AppTopBar(title: '搜索', onBack: widget.onBack),
      body: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.spacing.page,
              context.spacing.small,
              context.spacing.page,
              context.spacing.medium,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLength: maxSearchLength,
                    textInputAction: TextInputAction.search,
                    onChanged: viewModel.editInput,
                    onSubmitted: (_) => viewModel.submit(),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '搜索文章、技术与知识',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: state.input.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清空输入',
                              onPressed: () {
                                _controller.clear();
                                viewModel.editInput('');
                              },
                              icon: const Icon(Icons.close),
                            ),
                      filled: true,
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: context.spacing.small),
                FilledButton(
                  onPressed: state.canSubmit ? viewModel.submit : null,
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),
          Expanded(
            child: state.showResults
                ? NetworkListPage<Article>(
                    state: state.page,
                    emptyLabel: '没有找到相关文章',
                    onRefresh: viewModel.refresh,
                    onRetryInitial: viewModel.retryInitial,
                    onLoadMore: viewModel.loadMore,
                    onRetryLoadMore: viewModel.retryLoadMore,
                    onContinue: viewModel.continueAfterPause,
                    itemBuilder:
                        (BuildContext context, Article article, int _) =>
                            ArticleCard(
                              key: ValueKey<int>(article.id),
                              article: article,
                              onTap: () => widget.onArticleTap(article),
                            ),
                  )
                : _SearchSuggestions(
                    state: state,
                    onSelect: (String value) {
                      _controller.text = value;
                      _controller.selection = TextSelection.collapsed(
                        offset: value.length,
                      );
                      unawaited(viewModel.selectKeyword(value));
                    },
                    onClearHistory: () => _confirmClear(context, viewModel),
                    onRetry: viewModel.retrySuggestions,
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    SearchViewModel viewModel,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('清空搜索历史？'),
        content: const Text('此操作只会清除本机保存的搜索词。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) await viewModel.clearHistory();
  }
}

class _SearchSuggestions extends StatelessWidget {
  const _SearchSuggestions({
    required this.state,
    required this.onSelect,
    required this.onClearHistory,
    required this.onRetry,
  });

  final SearchUiState state;
  final ValueChanged<String> onSelect;
  final VoidCallback onClearHistory;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.symmetric(horizontal: context.spacing.page),
    children: <Widget>[
      if (state.suggestions.history.items.isNotEmpty) ...<Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '搜索历史',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: '清空搜索历史',
              onPressed: onClearHistory,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        Wrap(
          spacing: context.spacing.small,
          children: state.suggestions.history.items
              .map(
                (String value) => ActionChip(
                  label: Text(value),
                  onPressed: () => onSelect(value),
                ),
              )
              .toList(growable: false),
        ),
      ],
      SizedBox(height: context.spacing.medium),
      Text('热门搜索', style: Theme.of(context).textTheme.titleMedium),
      SizedBox(height: context.spacing.small),
      if (state.suggestions.hotLoading)
        const Center(child: CircularProgressIndicator())
      else if (state.suggestions.hotError != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onRetry,
            child: const Text('热门搜索加载失败，点击重试'),
          ),
        )
      else
        Wrap(
          spacing: context.spacing.small,
          runSpacing: context.spacing.small,
          children: state.suggestions.hotKeys
              .map(
                (String value) => ActionChip(
                  label: Text(value),
                  onPressed: () => onSelect(value),
                ),
              )
              .toList(growable: false),
        ),
      if (state.suggestions.history.readFailed ||
          state.suggestions.historyWriteFailed)
        Padding(
          padding: EdgeInsets.only(top: context.spacing.medium),
          child: Text(
            '本地搜索历史暂时不可用',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}
