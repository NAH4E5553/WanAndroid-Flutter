import 'package:flutter/widgets.dart';
import 'package:wanandroid_flutter/src/features/reader/view/article_reader_screen.dart';

Widget buildArticleReaderScreen({
  required int? articleId,
  required String title,
  required String url,
  required VoidCallback onExit,
  required VoidCallback onPopped,
  CollectMenuState? Function()? collectState,
  void Function(CollectionCollectIntent intent)? onToggleCollect,
  VoidCallback? onLogin,
}) => ArticleReaderScreen(
  articleId: articleId,
  title: title,
  url: url,
  onExit: onExit,
  onPopped: onPopped,
  collectState: collectState,
  onToggleCollect: onToggleCollect,
  onLogin: onLogin,
);

/// Collect-state snapshot the app layer provides to the reader menu.
class CollectMenuState {
  const CollectMenuState({
    this.authenticated = false,
    this.collected,
    this.busy = false,
    this.generation,
  });

  final bool authenticated;
  final bool? collected;
  final bool busy;
  final int? generation;
}

/// A user collect toggle for an internal article (articleId non-null).
class CollectionCollectIntent {
  const CollectionCollectIntent({
    required this.articleId,
    required this.collected,
    required this.generation,
  });

  final int? articleId;
  final bool? collected;
  final int generation;
}
