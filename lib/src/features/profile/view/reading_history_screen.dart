import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/reader/reading_history_provider.dart';
import 'package:wanandroid_flutter/src/core/ui/app_scaffold.dart';
import 'package:wanandroid_flutter/src/core/ui/app_top_bar.dart';
import 'package:wanandroid_flutter/src/core/ui/swipe_reveal_action_item.dart';
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
  final List<ReadingHistoryEntry> _entries = [];
  StreamSubscription<int>? _subscription;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;
  String? _revealedUrl;
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _subscription = ref.read(readingHistoryRepositoryProvider).changes.listen(
        (_) {
          unawaited(_reload());
        },
      );
      unawaited(_reload());
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _reload() async {
    _loadEpoch++;
    _hasMore = true;
    await _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    if (!_hasMore) return;
    final int epoch = _loadEpoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref
          .read(readingHistoryRepositoryProvider)
          .page(offset: reset ? 0 : _entries.length);
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        if (reset) _entries.clear();
        _entries.addAll(rows);
        _hasMore = rows.length == 20;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _delete(String url) async {
    try {
      await ref.read(readingHistoryRepositoryProvider).delete(url);
      if (mounted) setState(() => _revealedUrl = null);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
      }
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
    try {
      await ref.read(readingHistoryRepositoryProvider).clear();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('清空失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
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
            onPressed: _entries.isEmpty ? null : _clear,
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
          if (notification.metrics.extentAfter < 300 && !_loading && _hasMore) {
            unawaited(_load());
          }
          return false;
        },
        child: _entries.isEmpty && _loading
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty && _error != null
            ? Center(
                child: TextButton(
                  onPressed: _reload,
                  child: const Text('加载失败，点击重试'),
                ),
              )
            : _entries.isEmpty
            ? const Center(child: Text('暂无阅读历史'))
            : ListView.builder(
                itemCount: _entries.length + 1,
                itemBuilder: (context, index) {
                  if (index == _entries.length) {
                    if (_error != null) {
                      return TextButton(
                        onPressed: () => _load(),
                        child: const Text('加载更多失败，点击重试'),
                      );
                    }
                    return _loading
                        ? const Center(child: CircularProgressIndicator())
                        : const SizedBox.shrink();
                  }
                  final entry = _entries[index];
                  return _HistoryRow(
                    key: ValueKey(entry.url),
                    entry: entry,
                    revealed: _revealedUrl == entry.url,
                    onReveal: () => setState(() => _revealedUrl = entry.url),
                    onClose: () => setState(() => _revealedUrl = null),
                    onDelete: () => _delete(entry.url),
                    onRead: () =>
                        widget.onRead(entry.url, entry.title, entry.articleId),
                  );
                },
              ),
      ),
    ),
  );
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
