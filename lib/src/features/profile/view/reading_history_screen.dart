import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/ui/app_scaffold.dart';
import 'package:wanandroid_flutter/src/core/ui/app_top_bar.dart';
import 'package:wanandroid_flutter/src/core/ui/swipe_reveal_action_item.dart';
import 'package:wanandroid_flutter/src/features/profile/view_model/reading_history_view_model.dart';
import 'package:wanandroid_flutter/src/model/reading_history_entry.dart';

class ReadingHistoryScreen extends ConsumerStatefulWidget {
  const ReadingHistoryScreen({
    required this.onBack,
    required this.onPopped,
    required this.onRead,
    super.key,
  });

  final VoidCallback onBack;
  final VoidCallback onPopped;
  final void Function(String url, String title, int? articleId) onRead;

  @override
  ConsumerState<ReadingHistoryScreen> createState() =>
      _ReadingHistoryScreenState();
}

class _ReadingHistoryScreenState extends ConsumerState<ReadingHistoryScreen> {
  String? _revealedUrl;

  Future<void> _delete(String url) async {
    final bool deleted = await ref
        .read(readingHistoryViewModelProvider.notifier)
        .delete(url);
    if (!mounted) return;
    if (deleted) {
      setState(() => _revealedUrl = null);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
    }
  }

  Future<void> _clear() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空阅读历史？'),
        content: const Text('此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final bool cleared = await ref
        .read(readingHistoryViewModelProvider.notifier)
        .clear();
    if (!cleared && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('清空失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ReadingHistoryUiState state = ref.watch(
      readingHistoryViewModelProvider,
    );
    return PopScope<void>(
      onPopInvokedWithResult: (bool didPop, void result) {
        if (didPop) widget.onPopped();
      },
      child: AppScaffold(
        topBar: AppTopBar(
          title: '阅读历史',
          onBack: widget.onBack,
          actions: [
            IconButton(
              tooltip: '清空历史',
              onPressed: state.entries.isEmpty ? null : _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ),
        body: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification &&
                notification.dragDetails != null &&
                _revealedUrl != null) {
              setState(() => _revealedUrl = null);
            }
            if (notification.metrics.extentAfter < 300 &&
                !state.loading &&
                state.hasMore) {
              unawaited(
                ref.read(readingHistoryViewModelProvider.notifier).loadMore(),
              );
            }
            return false;
          },
          child: state.entries.isEmpty && state.loading
              ? const Center(child: CircularProgressIndicator())
              : state.entries.isEmpty && state.error != null
              ? Center(
                  child: TextButton(
                    onPressed: () => unawaited(
                      ref
                          .read(readingHistoryViewModelProvider.notifier)
                          .reload(),
                    ),
                    child: const Text('加载失败，点击重试'),
                  ),
                )
              : state.entries.isEmpty
              ? const Center(child: Text('暂无阅读历史'))
              : ListView.builder(
                  itemCount: state.entries.length + 1,
                  itemBuilder: (context, index) {
                    if (index == state.entries.length) {
                      if (state.error != null) {
                        return TextButton(
                          onPressed: () => unawaited(
                            ref
                                .read(readingHistoryViewModelProvider.notifier)
                                .loadMore(),
                          ),
                          child: const Text('加载更多失败，点击重试'),
                        );
                      }
                      return state.loading
                          ? const Center(child: CircularProgressIndicator())
                          : const SizedBox.shrink();
                    }
                    final entry = state.entries[index];
                    return _HistoryRow(
                      key: ValueKey(entry.url),
                      entry: entry,
                      revealed: _revealedUrl == entry.url,
                      onReveal: () => setState(() => _revealedUrl = entry.url),
                      onClose: () => setState(() => _revealedUrl = null),
                      onDelete: () => _delete(entry.url),
                      onRead: () => widget.onRead(
                        entry.url,
                        entry.title,
                        entry.articleId,
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatefulWidget {
  const _HistoryRow({
    required this.entry,
    required this.revealed,
    required this.onReveal,
    required this.onClose,
    required this.onDelete,
    required this.onRead,
    super.key,
  });

  final ReadingHistoryEntry entry;
  final bool revealed;
  final VoidCallback onReveal;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final VoidCallback onRead;

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  @override
  Widget build(BuildContext context) => SwipeRevealActionItem(
    revealed: widget.revealed,
    onReveal: widget.onReveal,
    onClose: widget.onClose,
    actionTooltip: '删除历史',
    onAction: widget.onDelete,
    actionIcon: Icons.delete_outline,
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        title: Text(
          widget.entry.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: const Text('仅保存在本机'),
        onTap: widget.revealed ? widget.onClose : widget.onRead,
      ),
    ),
  );
}
