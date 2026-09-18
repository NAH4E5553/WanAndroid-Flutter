import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/home_repository.dart';
import 'package:wanandroid_flutter/src/features/home/state/home_ui_state.dart';
import 'package:wanandroid_flutter/src/model/home_feed.dart';

final Provider<HomeRepository> homeRepositoryProvider =
    Provider<HomeRepository>(
      (Ref ref) =>
          throw StateError('HomeRepository must be provided by bootstrap.'),
    );

final AsyncNotifierProvider<HomeViewModel, HomeUiState> homeViewModelProvider =
    AsyncNotifierProvider<HomeViewModel, HomeUiState>(HomeViewModel.new);

class HomeViewModel extends AsyncNotifier<HomeUiState> {
  @override
  Future<HomeUiState> build() => _load();

  Future<void> refresh() async {
    state = const AsyncLoading<HomeUiState>();
    state = await AsyncValue.guard<HomeUiState>(_load);
  }

  Future<HomeUiState> _load() async {
    final HomeFeed feed = await ref.read(homeRepositoryProvider).loadHome();
    return HomeUiState(questions: feed.questions, articles: feed.articles);
  }
}
