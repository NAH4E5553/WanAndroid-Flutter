import 'package:flutter/widgets.dart';
import 'package:wanandroid_flutter/src/features/reader/view/article_reader_screen.dart';

Widget buildArticleReaderScreen({
  required int? articleId,
  required String title,
  required String url,
  required VoidCallback onExit,
  required VoidCallback onPopped,
  VoidCallback? onLogin,
}) => ArticleReaderScreen(
  articleId: articleId,
  title: title,
  url: url,
  onExit: onExit,
  onPopped: onPopped,
  onLogin: onLogin,
);
