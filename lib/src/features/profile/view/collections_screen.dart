import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/ui/app_scaffold.dart';
import 'package:wanandroid_flutter/src/core/ui/app_top_bar.dart';
import 'package:wanandroid_flutter/src/core/ui/article_card.dart';
import 'package:wanandroid_flutter/src/core/ui/swipe_reveal_action_item.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/collection_repository.dart';
import 'package:wanandroid_flutter/src/model/collection.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

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
  static const int _firstPage = 0;
  List<CollectionItem> _items = <CollectionItem>[];
  int? _generation;
  int? _nextPage;
  bool _loading = true;
  bool _appending = false;
  DataError? _error;
  final Set<String> _busyKeys = <String>{};
  final Set<String> _revealedKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _repository = ref.read(collectionRepositoryProvider);
    _repository.addListener(_onCollectionChanged);
    unawaited(_refresh());
  }

  late final CollectionRepository _repository;

  @override
  void dispose() {
    _repository.removeListener(_onCollectionChanged);
    super.dispose();
  }

  void _onCollectionChanged() {
    if (!mounted) {
      return;
    }
    final CollectionSnapshot snapshot = _repository.current;
    setState(() {
      _busyKeys
        ..clear()
        ..addAll(
          snapshot.statuses.entries
              .where((MapEntry<String, CollectionStatus> e) => e.value.busy)
              .map((MapEntry<String, CollectionStatus> e) => e.key),
        );
      if (snapshot.generation == null) {
        _items = const <CollectionItem>[];
        _generation = null;
      }
    });
  }

  Future<void> _refresh() async {
    final int? generation = _repository.current.generation;
    if (generation == null) {
      setState(() {
        _loading = false;
        _generation = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _generation = generation;
    });
    final DataResult<PageResult<CollectionItem>> result = await _repository
        .page(generation, _firstPage);
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _loading = false;
      if (result is DataSuccess<PageResult<CollectionItem>>) {
        _items = result.value.items;
        _nextPage = result.value.nextPage;
      } else {
        _error = (result as DataFailure<PageResult<CollectionItem>>).error;
      }
    });
  }

  Future<void> _loadMore() async {
    final int generation = _generation!;
    if (_appending || _nextPage == null) {
      return;
    }
    setState(() => _appending = true);
    final DataResult<PageResult<CollectionItem>> result = await _repository
        .page(generation, _nextPage!);
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _appending = false;
      if (result is DataSuccess<PageResult<CollectionItem>>) {
        _items = <CollectionItem>[..._items, ...result.value.items];
        _nextPage = result.value.nextPage;
      }
    });
  }

  Future<void> _remove(CollectionItem item) async {
    final int? generation = _repository.current.generation;
    if (generation == null) {
      return;
    }
    final DataResult<void> result = await _repository.setCollected(
      generation,
      item.target,
      false,
    );
    if (!mounted) {
      return;
    }
    if (result is DataSuccess<void>) {
      setState(() {
        _items = _items
            .where((CollectionItem e) => e.target.key != item.target.key)
            .toList(growable: false);
        _revealedKeys.remove(item.target.key);
      });
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('取消收藏失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AppScaffold(
      topBar: AppTopBar(title: '我的收藏', onBack: widget.onBack),
      body: builder(context, theme),
    );
  }

  Widget builder(BuildContext context, ThemeData theme) {
    if (_generation == null) {
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: <Widget>[
            const Text('加载失败'),
            FilledButton(onPressed: _refresh, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('还没有收藏，阅读文章时可以添加收藏'));
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification.metrics.pixels >
                notification.metrics.maxScrollExtent - 200 &&
            _nextPage != null &&
            !_appending &&
            !_loading) {
          unawaited(_loadMore());
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
        itemCount: _items.length + (_nextPage != null ? 1 : 1),
        itemBuilder: (BuildContext context, int index) {
          if (index >= _items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  _nextPage == null ? '已经到底了' : '正在加载…',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            );
          }
          final CollectionItem item = _items[index];
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
            onAction: _busyKeys.contains(item.target.key)
                ? null
                : () => _remove(item),
            child: ArticleCard(
              article: item.article,
              padding: EdgeInsets.zero,
              onTap: _busyKeys.contains(item.target.key)
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
