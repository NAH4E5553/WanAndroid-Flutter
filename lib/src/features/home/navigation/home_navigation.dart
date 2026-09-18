import 'package:flutter/widgets.dart';
import 'package:wanandroid_flutter/src/features/home/view/home_preview_screen.dart';
import 'package:wanandroid_flutter/src/features/home/view/home_screen.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

Widget buildHomeScreen({required ValueChanged<Article> onArticleTap}) =>
    HomeScreen(onArticleTap: onArticleTap);

Widget buildHomePreviewScreen({
  required int articleId,
  required String title,
  required VoidCallback onBack,
  required VoidCallback onPopped,
}) => HomePreviewScreen(
  articleId: articleId,
  title: title,
  onBack: onBack,
  onPopped: onPopped,
);
