import 'package:wanandroid_flutter/src/data/network/dto/article_dto.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

Article mapArticle(ArticleDto dto) => Article(
  id: dto.id,
  title: dto.title,
  url: dto.link,
  author: dto.author ?? '',
  shareUser: dto.shareUser ?? '',
  superChapterName: dto.superChapterName ?? '',
  chapter: dto.chapterName ?? '',
  publishedAt: dto.niceDate ?? '',
  collected: dto.collect,
);
