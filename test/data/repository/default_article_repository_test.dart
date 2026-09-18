import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/network/article_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_article_repository.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

void main() {
  test('maps page DTO fields and advances from the requested page', () async {
    final DefaultArticleRepository repository = DefaultArticleRepository(
      _FixtureArticleNetworkDataSource(),
    );
    final DataResult<PageResult<Article>> result = await repository.articles(
      0,
      DefaultRequestCancellationController().signal,
    );

    final PageResult<Article> page =
        (result as DataSuccess<PageResult<Article>>).value;
    expect(page.nextPage, 1);
    expect(page.items.single.id, 101);
    expect(page.items.single.chapter, 'Flutter');
    expect(page.items.single.author, '作者');
  });

  test(
    'question summary starts at page 1, deduplicates and takes five',
    () async {
      final _FixtureArticleNetworkDataSource source =
          _FixtureArticleNetworkDataSource(questionCount: 7);
      final DefaultArticleRepository repository = DefaultArticleRepository(
        source,
      );

      final DataResult<List<Article>> result = await repository.questions(
        DefaultRequestCancellationController().signal,
      );

      expect(source.questionPages, <int>[1]);
      expect((result as DataSuccess<List<Article>>).value.length, 5);
    },
  );

  test('invalid required page fields fail closed', () async {
    final DefaultArticleRepository repository = DefaultArticleRepository(
      _FixtureArticleNetworkDataSource(invalidPage: true),
    );

    final DataResult<PageResult<Article>> result = await repository.articles(
      0,
      DefaultRequestCancellationController().signal,
    );

    expect(
      (result as DataFailure<PageResult<Article>>).error,
      DataError.invalidResponse,
    );
  });
}

class _FixtureArticleNetworkDataSource implements ArticleNetworkDataSource {
  _FixtureArticleNetworkDataSource({
    this.questionCount = 1,
    this.invalidPage = false,
  });

  final int questionCount;
  final bool invalidPage;
  final List<int> questionPages = <int>[];

  @override
  Future<Map<String, dynamic>> articles(
    int page,
    RequestCancellation cancellation,
  ) async => <String, dynamic>{
    'errorCode': 0,
    'data': invalidPage ? <String, dynamic>{'datas': 'bad'} : _page(<int>[101]),
  };

  @override
  Future<Map<String, dynamic>> questions(
    int page,
    RequestCancellation cancellation,
  ) async {
    questionPages.add(page);
    return <String, dynamic>{
      'errorCode': 0,
      'data': _page(
        List<int>.generate(questionCount, (int index) => index + 1),
      ),
    };
  }

  @override
  Future<Map<String, dynamic>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) => articles(page, cancellation);

  @override
  Future<Map<String, dynamic>> hotKeys(
    RequestCancellation cancellation,
  ) async => <String, dynamic>{'errorCode': 0, 'data': <Object>[]};

  Map<String, dynamic> _page(List<int> ids) => <String, dynamic>{
    'datas': ids.map(_article).toList(growable: false),
    'curPage': 1,
    'over': false,
    'total': ids.length,
  };

  Map<String, dynamic> _article(int id) => <String, dynamic>{
    'id': id,
    'title': '文章$id',
    'link': 'https://fixture.invalid/$id',
    'author': '作者',
    'shareUser': '',
    'superChapterName': '开发',
    'chapterName': 'Flutter',
    'niceDate': '2026-09-18',
    'collect': false,
  };
}
