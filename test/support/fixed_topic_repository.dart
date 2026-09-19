import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/topic_repository.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';
import 'package:wanandroid_flutter/src/model/topic.dart';

class FixedTopicRepository implements TopicRepository {
  const FixedTopicRepository({this.articlesPerPage = 1});

  final int articlesPerPage;

  @override
  Future<DataResult<List<Topic>>> topics(
    RequestCancellation cancellation,
  ) async => const DataSuccess<List<Topic>>(<Topic>[
    Topic(id: 10, name: '开发语言'),
    Topic(id: 11, name: 'Flutter', parentId: 10),
    Topic(id: 12, name: 'Dart', parentId: 10),
    Topic(id: 20, name: '移动开发'),
    Topic(id: 21, name: 'Android', parentId: 20),
  ]);

  @override
  Future<DataResult<PageResult<Article>>> articles(
    int categoryId,
    int page,
    RequestCancellation cancellation,
  ) async => DataSuccess<PageResult<Article>>(
    PageResult<Article>(
      items: <Article>[
        for (int index = 0; index < articlesPerPage; index++)
          Article(
            id: categoryId * 1000 + page * 100 + index,
            title: index == 0 ? '专题文章 $categoryId' : '专题文章 $categoryId-$index',
            url: '',
            author: '固定作者',
            shareUser: '',
            superChapterName: '专题',
            chapter: '分类 $categoryId',
            publishedAt: '2026-09-19',
            collected: false,
          ),
      ],
      nextPage: null,
    ),
  );
}
