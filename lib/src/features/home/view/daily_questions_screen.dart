import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_state.dart';
import 'package:wanandroid_flutter/src/core/ui/app_scaffold.dart';
import 'package:wanandroid_flutter/src/core/ui/app_top_bar.dart';
import 'package:wanandroid_flutter/src/core/ui/article_card.dart';
import 'package:wanandroid_flutter/src/core/ui/network_list_page.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/daily_questions_view_model.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

class DailyQuestionsScreen extends ConsumerWidget {
  const DailyQuestionsScreen({
    required this.onBack,
    required this.onArticleTap,
    super.key,
  });

  final VoidCallback onBack;
  final ValueChanged<Article> onArticleTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PagedState<Article> state = ref.watch(
      dailyQuestionsViewModelProvider,
    );
    final DailyQuestionsViewModel viewModel = ref.read(
      dailyQuestionsViewModelProvider.notifier,
    );
    return AppScaffold(
      topBar: AppTopBar(title: '每日一问', onBack: onBack),
      body: NetworkListPage<Article>(
        state: state,
        onRefresh: viewModel.refresh,
        onRetryInitial: viewModel.retryInitial,
        onLoadMore: viewModel.loadMore,
        onRetryLoadMore: viewModel.retryLoadMore,
        onContinue: viewModel.continueAfterPause,
        itemBuilder: (BuildContext context, Article article, int _) =>
            ArticleCard(
              key: ValueKey<int>(article.id),
              article: article,
              onTap: () => onArticleTap(article),
            ),
      ),
    );
  }
}
