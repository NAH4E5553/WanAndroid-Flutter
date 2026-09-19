class ReadingHistoryEntry {
  const ReadingHistoryEntry({
    required this.url,
    required this.title,
    required this.lastReadAt,
    required this.articleId,
  });

  final String url;
  final String title;
  final DateTime lastReadAt;
  final int? articleId;
}
