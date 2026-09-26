import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/reader/reading_history_provider.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/reading_history_repository.dart';

final Provider<ReaderHistoryViewModel> readerHistoryViewModelProvider =
    Provider.autoDispose<ReaderHistoryViewModel>((Ref ref) {
      return ReaderHistoryViewModel(ref.read(readingHistoryRepositoryProvider));
    });

class ReaderHistoryViewModel {
  const ReaderHistoryViewModel(this._repository);

  final ReadingHistoryRepository _repository;

  Future<bool> record({
    required String url,
    required String title,
    int? articleId,
  }) async {
    try {
      await _repository.record(url: url, title: title, articleId: articleId);
      return true;
    } on Object {
      return false;
    }
  }
}
