import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/mapper/article_mapper.dart';
import 'package:wanandroid_flutter/src/data/mapper/wan_response_mapper.dart';
import 'package:wanandroid_flutter/src/data/network/article_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/network/dto/article_dto.dart';
import 'package:wanandroid_flutter/src/data/network/dto/wan_page_dto.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

final class DefaultArticleRepository implements ArticleRepository {
  const DefaultArticleRepository(this._source);

  static const int firstQuestionPage = 1;
  static const int homeQuestionLimit = 5;

  final ArticleNetworkDataSource _source;

  @override
  Future<DataResult<PageResult<Article>>> articles(
    int page,
    RequestCancellation cancellation,
  ) => _page(
    page: page,
    cancellation: cancellation,
    request: () => _source.articles(page, cancellation),
  );

  @override
  Future<DataResult<List<Article>>> questions(
    RequestCancellation cancellation,
  ) async {
    final DataResult<PageResult<Article>> result = await questionPage(
      firstQuestionPage,
      cancellation,
    );
    return result.map<List<Article>>(
      (PageResult<Article> page) => page.items
          .take(homeQuestionLimit)
          .fold<Map<int, Article>>(<int, Article>{}, (
            Map<int, Article> unique,
            Article article,
          ) {
            unique[article.id] = article;
            return unique;
          })
          .values
          .toList(growable: false),
    );
  }

  @override
  Future<DataResult<PageResult<Article>>> questionPage(
    int page,
    RequestCancellation cancellation,
  ) => _page(
    page: page,
    cancellation: cancellation,
    request: () => _source.questions(page, cancellation),
  );

  @override
  Future<DataResult<PageResult<Article>>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) => _page(
    page: page,
    cancellation: cancellation,
    request: () => _source.search(page, keyword, cancellation),
  );

  Future<DataResult<PageResult<Article>>> _page({
    required int page,
    required RequestCancellation cancellation,
    required Future<Map<String, dynamic>> Function() request,
  }) => requestWithData<PageResult<Article>>(
    request: request,
    cancellation: cancellation,
    decode: (Object? data) {
      final WanPageDto<ArticleDto> dto = WanPageDto<ArticleDto>.fromJson(
        data,
        ArticleDto.fromJson,
      );
      cancellation.throwIfCancelled();
      return PageResult<Article>(
        items: dto.datas.map(mapArticle).toList(growable: false),
        nextPage: dto.over ? null : page + 1,
      );
    },
  );
}
