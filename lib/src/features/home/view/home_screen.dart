import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/core/ui/article_card.dart';
import 'package:wanandroid_flutter/src/core/ui/search_icon.dart';
import 'package:wanandroid_flutter/src/features/home/component/daily_question_card.dart';
import 'package:wanandroid_flutter/src/features/home/state/home_ui_state.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_view_model.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({required this.onArticleTap, super.key});

  final ValueChanged<Article> onArticleTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<HomeUiState> state = ref.watch(homeViewModelProvider);
    return state.when(
      skipLoadingOnRefresh: true,
      data: (HomeUiState data) => _HomeContent(
        state: data,
        onArticleTap: onArticleTap,
        onRefresh: () => ref.read(homeViewModelProvider.notifier).refresh(),
      ),
      error: (Object error, StackTrace stackTrace) =>
          _HomeError(onRetry: () => ref.invalidate(homeViewModelProvider)),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.state,
    required this.onArticleTap,
    required this.onRefresh,
  });

  final HomeUiState state;
  final ValueChanged<Article> onArticleTap;
  final RefreshCallback onRefresh;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: CustomScrollView(
      key: const PageStorageKey<String>('home-scroll'),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: _SearchEntry(onTap: () => _showStageNotice(context)),
        ),
        SliverToBoxAdapter(
          child: _DailyQuestionSection(
            questions: state.questions,
            onArticleTap: onArticleTap,
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
        SliverList.builder(
          itemCount: state.articles.length,
          itemBuilder: (BuildContext context, int index) {
            final Article article = state.articles[index];
            return ArticleCard(
              key: ValueKey<int>(article.id),
              article: article,
              onTap: () => onArticleTap(article),
            );
          },
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(context.spacing.section),
            child: Center(
              child: Text(
                '固定 Fake 数据 · 阶段 1',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  void _showStageNotice(BuildContext context) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('搜索将在阶段 2 接入')));
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

class _DailyQuestionSection extends StatelessWidget {
  const _DailyQuestionSection({
    required this.questions,
    required this.onArticleTap,
  });

  final List<Article> questions;
  final ValueChanged<Article> onArticleTap;

  @override
  Widget build(BuildContext context) {
    final Article question = questions.first;
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
                  onPressed: () => onArticleTap(question),
                  child: const Text('查看更多'),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.page),
            child: DailyQuestionCard(
              question: question,
              position: 0,
              count: questions.length,
              onTap: () => onArticleTap(question),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeError extends StatelessWidget {
  const _HomeError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: context.spacing.small,
      children: <Widget>[
        const Text('固定数据加载失败'),
        FilledButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}
