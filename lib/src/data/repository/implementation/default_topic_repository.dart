import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/mapper/article_mapper.dart';
import 'package:wanandroid_flutter/src/data/mapper/wan_response_mapper.dart';
import 'package:wanandroid_flutter/src/data/network/article_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/network/dto/article_dto.dart';
import 'package:wanandroid_flutter/src/data/network/dto/wan_page_dto.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/collection_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/topic_repository.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';
import 'package:wanandroid_flutter/src/model/topic.dart';

final class DefaultTopicRepository implements TopicRepository {
  DefaultTopicRepository(this._source, [CollectionRepository? collections])
    : _collections = collections;

  final CollectionRepository? _collections;

  Future<DataResult<PageResult<Article>>> _merge(
    Future<DataResult<PageResult<Article>>> Function() load,
  ) {
    final CollectionRepository? collections = _collections;
    return collections == null ? load() : collections.articlePage(load);
  }

  final ArticleNetworkDataSource _source;

  @override
  Future<DataResult<List<Topic>>> topics(RequestCancellation cancellation) =>
      requestWithData<List<Topic>>(
        request: () => _source.topics(cancellation),
        cancellation: cancellation,
        decode: (Object? data) {
          if (data is! List<Object?>) {
            throw const FormatException('Invalid topic tree');
          }
          final Map<int, Topic> topics = <int, Topic>{};
          for (final Object? rawParent in data) {
            final Map<String, dynamic> parent = _topicMap(rawParent);
            final int parentId = _topicId(parent);
            topics.putIfAbsent(
              parentId,
              () => Topic(id: parentId, name: _topicName(parent)),
            );
            final Object? rawChildren = parent['children'] ?? const <Object?>[];
            if (rawChildren is! List<Object?>) {
              throw const FormatException('Invalid topic children');
            }
            for (final Object? rawChild in rawChildren) {
              final Map<String, dynamic> child = _topicMap(rawChild);
              final int childId = _topicId(child);
              topics.putIfAbsent(
                childId,
                () => Topic(
                  id: childId,
                  name: _topicName(child),
                  parentId: parentId,
                ),
              );
            }
          }
          cancellation.throwIfCancelled();
          return topics.values.toList(growable: false);
        },
      );

  @override
  Future<DataResult<PageResult<Article>>> articles(
    int categoryId,
    int page,
    RequestCancellation cancellation,
  ) => _merge(
    () => requestWithData<PageResult<Article>>(
      request: () => _source.topicArticles(categoryId, page, cancellation),
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
    ),
  );
}

Map<String, dynamic> _topicMap(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('Invalid topic');
  }
  return raw;
}

int _topicId(Map<String, dynamic> raw) {
  final Object? value = raw['id'];
  if (value is! int || value <= 0) {
    throw const FormatException('Invalid topic id');
  }
  return value;
}

String _topicName(Map<String, dynamic> raw) {
  final Object? value = raw['name'];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid topic name');
  }
  return value;
}
