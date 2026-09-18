// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'article_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ArticleDto _$ArticleDtoFromJson(Map<String, dynamic> json) => ArticleDto(
  id: (json['id'] as num).toInt(),
  title: json['title'] as String,
  link: json['link'] as String,
  author: json['author'] as String?,
  shareUser: json['shareUser'] as String?,
  superChapterName: json['superChapterName'] as String?,
  chapterName: json['chapterName'] as String?,
  niceDate: json['niceDate'] as String?,
  collect: json['collect'] as bool? ?? false,
);
