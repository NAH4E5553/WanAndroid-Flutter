import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_state.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/core/ui/article_card.dart';
import 'package:wanandroid_flutter/src/core/ui/search_icon.dart';
import 'package:wanandroid_flutter/src/features/home/component/daily_question_card.dart';
import 'package:wanandroid_flutter/src/features/home/state/home_ui_state.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_view_model.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    required this.onArticleTap,
    required this.onSearchTap,
    required this.onViewAllQuestions,
    super.key,
  });

  final ValueChanged<Article> onArticleTap;
  final VoidCallback onSearchTap;
  final VoidCallback onViewAllQuestions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HomeUiState state = ref.watch(homeViewModelProvider);
    final HomeViewModel viewModel = ref.read(homeViewModelProvider.notifier);
    final PagedState<Article> articles = state.articles;
    if (articles.items.isEmpty && articles.isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (articles.items.isEmpty && articles.initialError != null) {
      return _HomeInitialError(onRetry: viewModel.retryInitial);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification.metrics.extentAfter < 480) {
          unawaited(viewModel.loadMore());
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: viewModel.refresh,
        child: CustomScrollView(
          key: const PageStorageKey<String>('home-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverToBoxAdapter(child: _SearchEntry(onTap: onSearchTap)),
            SliverToBoxAdapter(
              child: _DailyQuestionSection(
                state: state.questions,
                onArticleTap: onArticleTap,
                onViewAll: onViewAllQuestions,
                onRetry: viewModel.retryQuestions,
                visible: state.visible,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  context.spacing.page,
                  context.spacing.small,
                  context.spacing.page,
                  context.spacing.medium,
                ),
                child: Text(
                  '最新博文',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
            if (articles.items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('暂无文章')),
              )
            else
              SliverList.builder(
                itemCount: articles.items.length,
                itemBuilder: (BuildContext context, int index) {
                  final Article article = articles.items[index];
                  return ArticleCard(
                    key: ValueKey<int>(article.id),
                    article: article,
                    onTap: () => onArticleTap(article),
                  );
                },
              ),
            SliverToBoxAdapter(
              child: _HomeFooter(
                state: articles,
                onRetry: viewModel.retryLoadMore,
                onContinue: viewModel.continueAfterPause,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: context.spacing.page,
      vertical: context.spacing.small,
    ),
    child: Semantics(
      button: true,
      label: '搜索文章、技术与知识',
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: context.spacing.page),
              child: Row(
                spacing: context.spacing.medium,
                children: <Widget>[
                  const AppSearchIcon(),
                  Expanded(
                    child: Text(
                      '搜索文章、技术与知识',
                      style: Theme.of(context).textTheme.bodyLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _DailyQuestionSection extends StatefulWidget {
  const _DailyQuestionSection({
    required this.state,
    required this.onArticleTap,
    required this.onViewAll,
    required this.onRetry,
    required this.visible,
  });

  final QuestionUiState state;
  final ValueChanged<Article> onArticleTap;
  final VoidCallback onViewAll;
  final VoidCallback onRetry;
  final bool visible;

  @override
  State<_DailyQuestionSection> createState() => _DailyQuestionSectionState();
}

class _DailyQuestionSectionState extends State<_DailyQuestionSection> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _position = 0;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _DailyQuestionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible ||
        oldWidget.state.items.length != widget.state.items.length) {
      _syncTimer();
    }
  }

  void _syncTimer() {
    _timer?.cancel();
    if (!widget.visible || widget.state.items.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients) return;
      final int next = (_position + 1) % widget.state.items.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 320),
        curve: Curves.fastOutSlowIn,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double textScaleGrowth =
        (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0, 1).toDouble();
    return Padding(
      padding: EdgeInsets.only(bottom: context.spacing.section),
      child: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.page),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '每日一问',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                TextButton(
                  onPressed: widget.onViewAll,
                  child: const Text('查看更多'),
                ),
              ],
            ),
          ),
          if (widget.state.items.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.spacing.page),
              child: SizedBox(
                height: 156 + (72 * textScaleGrowth),
                child: PageView.builder(
                  controller: _controller,
                  itemCount: widget.state.items.length,
                  onPageChanged: (int value) {
                    setState(() => _position = value);
                  },
                  itemBuilder: (BuildContext context, int index) {
                    final Article question = widget.state.items[index];
                    return DailyQuestionCard(
                      question: question,
                      position: index,
                      count: widget.state.items.length,
                      onTap: () => widget.onArticleTap(question),
                    );
                  },
                ),
              ),
            )
          else if (widget.state.loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else if (widget.state.error != null)
            TextButton(
              onPressed: widget.onRetry,
              child: const Text('每日一问加载失败，点击重试'),
            )
          else
            const Padding(padding: EdgeInsets.all(16), child: Text('暂无每日一问')),
        ],
      ),
    );
  }
}

class _HomeFooter extends StatelessWidget {
  const _HomeFooter({
    required this.state,
    required this.onRetry,
    required this.onContinue,
  });

  final PagedState<Article> state;
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
    return Padding(
      padding: EdgeInsets.all(context.spacing.section),
      child: Center(child: Text(state.canLoadMore ? '继续滑动加载' : '已经到底了')),
    );
  }
}

class _HomeInitialError extends StatelessWidget {
  const _HomeInitialError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: context.spacing.small,
      children: <Widget>[
        const Text('首页加载失败'),
        FilledButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}
