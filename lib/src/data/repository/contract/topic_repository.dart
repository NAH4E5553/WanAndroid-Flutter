import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';
import 'package:wanandroid_flutter/src/model/topic.dart';

abstract interface class TopicRepository {
  Future<DataResult<List<Topic>>> topics(RequestCancellation cancellation);

  Future<DataResult<PageResult<Article>>> articles(
    int categoryId,
    int page,
    RequestCancellation cancellation,
  );
}
