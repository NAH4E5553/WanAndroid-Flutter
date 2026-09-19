import 'package:wanandroid_flutter/src/model/reading_history_entry.dart';

abstract interface class ReadingHistoryRepository {
  Stream<int> get changes;
  Future<List<ReadingHistoryEntry>> page({int offset = 0, int limit = 20});
  Future<void> record({
    required String url,
    required String title,
    int? articleId,
  });
  Future<void> delete(String url);
  Future<void> clear();
}
