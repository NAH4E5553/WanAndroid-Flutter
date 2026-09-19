import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/network/article_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_topic_repository.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';
import 'package:wanandroid_flutter/src/model/topic.dart';

void main() {
  test('flattens real parent-child IDs without merging equal names', () async {
    final _TopicSource source = _TopicSource();
    final DefaultTopicRepository repository = DefaultTopicRepository(source);

    final DataResult<List<Topic>> result = await repository.topics(
      DefaultRequestCancellationController().signal,
    );

    final List<Topic> topics = (result as DataSuccess<List<Topic>>).value;
    expect(topics.map((Topic topic) => topic.id), <int>[10, 11, 12, 20, 21]);
    expect(topics[1].name, topics[2].name);
    expect(topics[1].parentId, 10);
    expect(topics[4].parentId, 20);
  });

  test('rejects malformed hierarchy and missing response data', () async {
    final _TopicSource source = _TopicSource();
    final DefaultTopicRepository repository = DefaultTopicRepository(source);
    source.tree = <String, dynamic>{
      'errorCode': 0,
      'data': <Object?>[
        <String, Object?>{'id': 10, 'name': 'A', 'children': 'bad'},
      ],
    };
    expect(
      (await repository.topics(
        DefaultRequestCancellationController().signal,
      ) as DataFailure<List<Topic>>).error,
      DataError.invalidResponse,
    );
    source.tree = <String, dynamic>{'errorCode': 0};
    expect(
      (await repository.topics(
        DefaultRequestCancellationController().signal,
      ) as DataFailure<List<Topic>>).error,
      DataError.invalidResponse,
    );
  });

  test('maps category page from zero and keeps its real cid', () async {
    final _TopicSource source = _TopicSource();
    final DefaultTopicRepository repository = DefaultTopicRepository(source);

    final DataResult<PageResult<Article>> result = await repository.articles(
      12,
      0,
      DefaultRequestCancellationController().signal,
    );

    final PageResult<Article> page =
        (result as DataSuccess<PageResult<Article>>).value;
    expect(source.lastCategory, 12);
    expect(source.lastPage, 0);
    expect(page.items.single.id, 120);
    expect(page.nextPage, 1);
  });

  test('cancellation before response does not publish a topic tree', () async {
    final _TopicSource source = _TopicSource();
    final DefaultTopicRepository repository = DefaultTopicRepository(source);
    final DefaultRequestCancellationController cancellation =
        DefaultRequestCancellationController()..cancel();

    await expectLater(
      repository.topics(cancellation.signal),
      throwsA(isA<RequestCancelledException>()),
    );
  });
}

class _TopicSource implements ArticleNetworkDataSource {
  Map<String, dynamic> tree = <String, dynamic>{
    'errorCode': 0,
    'data': <Object?>[
      <String, Object?>{
        'id': 10,
        'name': '开发语言',
        'children': <Object?>[
          <String, Object?>{'id': 11, 'name': '同名'},
          <String, Object?>{'id': 12, 'name': '同名'},
        ],
      },
      <String, Object?>{
        'id': 20,
        'name': '移动开发',
        'children': <Object?>[
          <String, Object?>{'id': 21, 'name': 'Android'},
        ],
      },
    ],
  };
  int? lastCategory;
  int? lastPage;

  @override
  Future<Map<String, dynamic>> topics(RequestCancellation cancellation) async =>
      tree;

  @override
  Future<Map<String, dynamic>> topicArticles(
    int categoryId,
    int page,
    RequestCancellation cancellation,
  ) async {
    lastCategory = categoryId;
    lastPage = page;
    return <String, dynamic>{
      'errorCode': 0,
      'data': <String, Object?>{
        'datas': <Object?>[
          <String, Object?>{
            'id': categoryId * 10 + page,
            'title': '固定文章',
            'link': 'https://fixture.invalid/article',
            'author': '作者',
            'shareUser': '',
            'superChapterName': '专题',
            'chapterName': '同名',
            'niceDate': '2026-09-19',
            'collect': false,
          },
        ],
        'curPage': page + 1,
        'over': false,
        'total': 2,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> articles(
    int page,
    RequestCancellation cancellation,
  ) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> questions(
    int page,
    RequestCancellation cancellation,
  ) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> hotKeys(RequestCancellation cancellation) =>
      throw UnimplementedError();
}
