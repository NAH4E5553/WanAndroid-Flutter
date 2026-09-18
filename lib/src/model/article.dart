class Article {
  const Article({
    required this.id,
    required this.title,
    required this.url,
    required this.author,
    required this.shareUser,
    required this.superChapterName,
    required this.chapter,
    required this.publishedAt,
    required this.collected,
  });

  final int id;
  final String title;
  final String url;
  final String author;
  final String shareUser;
  final String superChapterName;
  final String chapter;
  final String publishedAt;
  final bool collected;
}
