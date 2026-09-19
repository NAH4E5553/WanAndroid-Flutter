import 'package:flutter/widgets.dart';
import 'package:wanandroid_flutter/src/features/topics/view/topics_screen.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

Widget buildTopicsScreen({required ValueChanged<Article> onArticleTap}) =>
    TopicsScreen(onArticleTap: onArticleTap);
