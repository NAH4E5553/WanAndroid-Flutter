import 'package:json_annotation/json_annotation.dart';

part 'article_dto.g.dart';

@JsonSerializable(createToJson: false)
class ArticleDto {
  const ArticleDto({
    required this.id,
    required this.title,
    required this.link,
    this.author,
    this.shareUser,
    this.superChapterName,
    this.chapterName,
    this.niceDate,
    this.collect = false,
  });

  factory ArticleDto.fromJson(Map<String, dynamic> json) =>
      _$ArticleDtoFromJson(json);

  final int id;
  final String title;
  final String link;
  final String? author;
  final String? shareUser;
  final String? superChapterName;
  final String? chapterName;
  final String? niceDate;
  final bool collect;
}
