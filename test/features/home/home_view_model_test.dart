import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/home_repository.dart';
import 'package:wanandroid_flutter/src/features/home/state/home_ui_state.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_view_model.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/home_feed.dart';

void main() {
  test('loads fixed feed through the repository contract', () async {
    final _CountingHomeRepository repository = _CountingHomeRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: [homeRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final HomeUiState state = await container.read(
      homeViewModelProvider.future,
    );

    expect(state.articles.single.id, 101);
    expect(state.questions.single.id, 201);
    expect(repository.loadCount, 1);
  });

  test('refresh replaces state using the same contract', () async {
    final _CountingHomeRepository repository = _CountingHomeRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: [homeRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(homeViewModelProvider.future);

    await container.read(homeViewModelProvider.notifier).refresh();

    expect(repository.loadCount, 2);
    expect(
      container.read(homeViewModelProvider).requireValue.articles.single.id,
      101,
    );
  });
}

class _CountingHomeRepository implements HomeRepository {
  int loadCount = 0;

  @override
  Future<HomeFeed> loadHome() async {
    loadCount += 1;
    return const HomeFeed(
      questions: <Article>[
        Article(
          id: 201,
          title: 'Question',
          url: 'https://fixture.invalid/q',
          author: 'Author',
          shareUser: '',
          superChapterName: 'Q',
          chapter: 'Flutter',
          publishedAt: '2026-09-18',
          collected: false,
        ),
      ],
      articles: <Article>[
        Article(
          id: 101,
          title: 'Article',
          url: 'https://fixture.invalid/a',
          author: '',
          shareUser: 'Sharer',
          superChapterName: 'A',
          chapter: 'Flutter',
          publishedAt: '2026-09-18',
          collected: false,
        ),
      ],
    );
  }
}
