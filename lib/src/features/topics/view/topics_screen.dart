import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_state.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/core/ui/article_card.dart';
import 'package:wanandroid_flutter/src/core/ui/network_list_page.dart';
import 'package:wanandroid_flutter/src/features/topics/state/topics_ui_state.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_view_model.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/topic.dart';

class TopicsScreen extends ConsumerWidget {
  const TopicsScreen({required this.onArticleTap, super.key});

  final ValueChanged<Article> onArticleTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TopicsUiState state = ref.watch(topicsViewModelProvider);
    final TopicsViewModel viewModel = ref.read(
      topicsViewModelProvider.notifier,
    );
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.spacing.page,
                  vertical: context.spacing.medium,
                ),
                child: Text(
                  '专题',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            ),
          ),
          Expanded(
            child: switch ((
              state.loading,
              state.error,
              state.parents.isEmpty,
            )) {
              (true, _, _) => const Center(child: CircularProgressIndicator()),
              (false, final DataError error, _) => _TopicsMessage(
                message: _topicErrorLabel(error),
                action: '重试',
                onAction: viewModel.retryTopics,
              ),
              (false, _, true) => const _TopicsMessage(message: '暂无专题'),
              _ => _TopicsCategoryPane(
                key: ValueKey<int>(state.selectedParentId!),
                state: state,
                viewModel: viewModel,
                onArticleTap: onArticleTap,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _TopicsCategoryPane extends StatefulWidget {
  const _TopicsCategoryPane({
    required this.state,
    required this.viewModel,
    required this.onArticleTap,
    super.key,
  });

  final TopicsUiState state;
  final TopicsViewModel viewModel;
  final ValueChanged<Article> onArticleTap;

  @override
  State<_TopicsCategoryPane> createState() => _TopicsCategoryPaneState();
}

class _TopicsCategoryPaneState extends State<_TopicsCategoryPane>
    with SingleTickerProviderStateMixin {
  static const double menuWidth = 92;
  late final AnimationController _sidebar;
  late PageController _pager;
  late int _visualIndex;
  late bool _sidebarTargetExpanded;

  bool get _expanded =>
      widget.state.selectedId == widget.state.tabs.firstOrNull?.id;

  @override
  void initState() {
    super.initState();
    _visualIndex = widget.state.tabs
        .indexWhere((Topic topic) => topic.id == widget.state.selectedId)
        .clamp(0, widget.state.tabs.isEmpty ? 0 : widget.state.tabs.length - 1);
    _pager = PageController(initialPage: _visualIndex);
    _sidebarTargetExpanded = _expanded;
    _sidebar =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 320),
          value: _expanded ? 1 : 0,
        )..addListener(() {
          if (mounted) setState(() {});
        });
  }

  @override
  void didUpdateWidget(covariant _TopicsCategoryPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_expanded == _sidebarTargetExpanded) return;
    _sidebarTargetExpanded = _expanded;
    if (_expanded) {
      unawaited(_sidebar.animateTo(1, curve: Curves.fastOutSlowIn));
    } else {
      unawaited(_sidebar.animateTo(0, curve: Curves.fastOutSlowIn));
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    _sidebar.dispose();
    super.dispose();
  }

  void _settlePage() {
    if (!_pager.hasClients || widget.state.tabs.isEmpty) return;
    final int index = (_pager.page ?? _visualIndex).round().clamp(
      0,
      widget.state.tabs.length - 1,
    );
    widget.viewModel.selectChild(
      widget.state.selectedParentId!,
      widget.state.tabs[index].id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Topic> tabs = widget.state.tabs;
    return Row(
      key: const ValueKey<String>('topic-layout'),
      children: <Widget>[
        SizedBox(
          key: const ValueKey<String>('topic-menu-slot'),
          width: menuWidth * _sidebar.value,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: menuWidth,
              maxWidth: menuWidth,
              child: ExcludeSemantics(
                excluding: !_expanded,
                child: IgnorePointer(
                  ignoring: !_expanded,
                  child: Opacity(
                    key: const ValueKey<String>('topic-menu-fade'),
                    opacity: _sidebar.value,
                    child: Transform.translate(
                      offset: Offset(-menuWidth * (1 - _sidebar.value), 0),
                      child: SizedBox(
                        width: menuWidth,
                        child: _TopicMenu(
                          topics: widget.state.parents,
                          selectedId: widget.state.selectedParentId!,
                          onSelect: widget.viewModel.selectParent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: tabs.isEmpty
              ? const _TopicsMessage(message: '暂无子分类')
              : Column(
                  children: <Widget>[
                    _TopicTabs(
                      topics: tabs,
                      selectedIndex: _visualIndex,
                      onTap: (int index) {
                        unawaited(
                          _pager
                              .animateToPage(
                                index,
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeInOut,
                              )
                              .then((_) => _settlePage()),
                        );
                      },
                    ),
                    Expanded(
                      child: NotificationListener<ScrollEndNotification>(
                        onNotification: (ScrollEndNotification notification) {
                          if (notification.metrics.axis == Axis.horizontal) {
                            _settlePage();
                          }
                          return false;
                        },
                        child: PageView.builder(
                          key: const ValueKey<String>('topic-pager'),
                          controller: _pager,
                          physics: _sidebar.isAnimating || tabs.length < 2
                              ? const NeverScrollableScrollPhysics()
                              : const PageScrollPhysics(),
                          itemCount: tabs.length,
                          onPageChanged: (int index) {
                            setState(() => _visualIndex = index);
                          },
                          itemBuilder: (BuildContext context, int index) {
                            final Topic topic = tabs[index];
                            final bool active =
                                widget.state.selectedId == topic.id &&
                                _visualIndex == index &&
                                !_sidebar.isAnimating;
                            return NetworkListPage<Article>(
                              key: ValueKey<int>(topic.id),
                              scrollKey: PageStorageKey<int>(topic.id),
                              pagingEnabled: active,
                              state:
                                  widget.state.pageStates[topic.id] ??
                                  const PagedState<Article>(
                                    initial: LoadLoading(),
                                  ),
                              emptyLabel: '暂无文章',
                              onRefresh: () =>
                                  widget.viewModel.refresh(topic.id),
                              onRetryInitial: () => unawaited(
                                widget.viewModel.retryInitial(topic.id),
                              ),
                              onRetryRefresh: () => unawaited(
                                widget.viewModel.retryRefresh(topic.id),
                              ),
                              onLoadMore: () => unawaited(
                                widget.viewModel.loadMore(topic.id),
                              ),
                              onRetryLoadMore: () => unawaited(
                                widget.viewModel.retryAppend(topic.id),
                              ),
                              onContinue: () => unawaited(
                                widget.viewModel.continueAfterPause(topic.id),
                              ),
                              itemBuilder:
                                  (
                                    BuildContext context,
                                    Article article,
                                    int _,
                                  ) => ArticleCard(
                                    article: article,
                                    showCategory: false,
                                    onTap: () => widget.onArticleTap(article),
                                  ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _TopicTabs extends StatelessWidget {
  const _TopicTabs({
    required this.topics,
    required this.selectedIndex,
    required this.onTap,
  });

  final List<Topic> topics;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: ListView.builder(
      key: const ValueKey<String>('topic-tabs'),
      scrollDirection: Axis.horizontal,
      itemCount: topics.length,
      itemBuilder: (BuildContext context, int index) {
        final bool selected = selectedIndex == index;
        final ColorScheme colors = Theme.of(context).colorScheme;
        return Semantics(
          selected: selected,
          button: true,
          child: InkWell(
            key: ValueKey<String>('topic-tab-${topics[index].id}'),
            onTap: () => onTap(index),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 72),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.spacing.medium,
                        ),
                        child: Text(
                          topics[index].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: selected
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    height: 2,
                    color: selected ? colors.primary : Colors.transparent,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _TopicMenu extends StatelessWidget {
  const _TopicMenu({
    required this.topics,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Topic> topics;
  final int selectedId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: ListView.builder(
      key: const PageStorageKey<String>('topic-menu'),
      itemCount: topics.length,
      itemBuilder: (BuildContext context, int index) {
        final Topic topic = topics[index];
        final bool selected = topic.id == selectedId;
        final ColorScheme colors = Theme.of(context).colorScheme;
        return Semantics(
          selected: selected,
          button: true,
          child: InkWell(
            key: ValueKey<String>('topic-${topic.id}'),
            onTap: selected ? null : () => onSelect(topic.id),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: selected ? colors.surface : colors.surfaceContainerLow,
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 3,
                      height: 24,
                      child: ColoredBox(
                        color: selected ? colors.primary : Colors.transparent,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(7, 14, 10, 14),
                        child: Text(
                          topic.name,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: selected
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _TopicsMessage extends StatelessWidget {
  const _TopicsMessage({required this.message, this.action, this.onAction});

  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(message, textAlign: TextAlign.center),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

String _topicErrorLabel(DataError error) => switch (error) {
  DataError.network => '网络连接失败，请稍后重试',
  DataError.service => '服务暂时不可用，请稍后重试',
  _ => '专题加载失败，请稍后重试',
};
