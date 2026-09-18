import 'package:wanandroid_flutter/src/model/article.dart';

class HomeUiState {
  const HomeUiState({required this.questions, required this.articles});

  final List<Article> questions;
  final List<Article> articles;
}
