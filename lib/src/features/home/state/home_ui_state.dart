import 'package:wanandroid_flutter/src/core/paging/paging_state.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

class QuestionUiState {
  const QuestionUiState({
    this.items = const <Article>[],
    this.loading = true,
    this.error,
  });

  final List<Article> items;
  final bool loading;
  final DataError? error;
}

class HomeUiState {
  const HomeUiState({
    this.articles = const PagedState<Article>(initial: LoadLoading()),
    this.questions = const QuestionUiState(),
  });

  final PagedState<Article> articles;
  final QuestionUiState questions;

  bool get isPullRefreshing =>
      articles.isRefreshing ||
      (questions.items.isNotEmpty && questions.loading);

  HomeUiState copyWith({
    PagedState<Article>? articles,
    QuestionUiState? questions,
  }) => HomeUiState(
    articles: articles ?? this.articles,
    questions: questions ?? this.questions,
  );
}
