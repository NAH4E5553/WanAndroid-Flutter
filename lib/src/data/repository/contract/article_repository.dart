import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

abstract interface class ArticleRepository {
  Future<DataResult<PageResult<Article>>> articles(
    int page,
    RequestCancellation cancellation,
  );

  Future<DataResult<List<Article>>> questions(RequestCancellation cancellation);

  Future<DataResult<PageResult<Article>>> questionPage(
    int page,
    RequestCancellation cancellation,
  );

  Future<DataResult<PageResult<Article>>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  );
}
