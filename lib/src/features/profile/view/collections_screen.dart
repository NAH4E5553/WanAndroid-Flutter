import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/ui/app_scaffold.dart';
import 'package:wanandroid_flutter/src/core/ui/app_top_bar.dart';
import 'package:wanandroid_flutter/src/core/ui/article_card.dart';
import 'package:wanandroid_flutter/src/core/ui/swipe_reveal_action_item.dart';
import 'package:wanandroid_flutter/src/features/profile/view_model/collections_view_model.dart';
import 'package:wanandroid_flutter/src/model/collection.dart';

/// 我的收藏（UI-09）：统一文章卡片 + 左滑红色取消收藏；未登录引导登录。
class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({
    required this.onBack,
    required this.onLoginTap,
    required this.onArticleTap,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onLoginTap;
  final void Function(String url, String title, int? articleId) onArticleTap;

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  final Set<String> _revealedKeys = <String>{};

  Future<void> _remove(CollectionItem item) async {
    final bool removed = await ref
        .read(collectionsViewModelProvider.notifier)
        .remove(item);
    if (!mounted) return;
    if (removed) {
      setState(() => _revealedKeys.remove(item.target.key));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('取消收藏失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CollectionsUiState state = ref.watch(collectionsViewModelProvider);
    return AppScaffold(
      topBar: AppTopBar(title: '我的收藏', onBack: widget.onBack),
      body: builder(context, theme, state),
    );
  }

  Widget builder(
    BuildContext context,
    ThemeData theme,
    CollectionsUiState state,
  ) {
    if (state.generation == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: <Widget>[
            const Text('请登录后查看收藏'),
            FilledButton(onPressed: widget.onLoginTap, child: const Text('登录')),
          ],
        ),
      );
    }
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: <Widget>[
            const Text('加载失败'),
            FilledButton(
              onPressed: () => unawaited(
                ref.read(collectionsViewModelProvider.notifier).refresh(),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (state.items.isEmpty) {
      return const Center(child: Text('还没有收藏，阅读文章时可以添加收藏'));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification.metrics.pixels >
                notification.metrics.maxScrollExtent - 200 &&
            state.nextPage != null &&
            !state.appending &&
            !state.loading) {
          unawaited(ref.read(collectionsViewModelProvider.notifier).loadMore());
        }
        if (notification is ScrollUpdateNotification &&
            notification.scrollDelta != null &&
            notification.scrollDelta! > 0 &&
            _revealedKeys.isNotEmpty) {
          setState(() => _revealedKeys.clear());
        }
        return false;
      },
      child: ListView.builder(
        itemCount: state.items.length + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index >= state.items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  state.nextPage == null ? '已经到底了' : '正在加载…',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            );
          }
          final CollectionItem item = state.items[index];
          return SwipeRevealActionItem(
            key: ValueKey<String>(item.target.key),
            revealed: _revealedKeys.contains(item.target.key),
            onReveal: () => setState(() {
              _revealedKeys
                ..clear()
                ..add(item.target.key);
            }),
            onClose: () =>
                setState(() => _revealedKeys.remove(item.target.key)),
            actionTooltip: '取消收藏',
            actionIcon: Icons.star_border,
            onAction: state.busyKeys.contains(item.target.key)
                ? null
                : () => _remove(item),
            child: ArticleCard(
              article: item.article,
              padding: EdgeInsets.zero,
              onTap: state.busyKeys.contains(item.target.key)
                  ? () {}
                  : () => widget.onArticleTap(
                      item.article.url,
                      item.article.title,
                      item.target.articleId,
                    ),
            ),
          );
        },
      ),
    );
  }
}
