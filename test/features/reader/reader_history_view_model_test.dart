import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/reader/reading_history_provider.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/reading_history_repository.dart';
import 'package:wanandroid_flutter/src/features/reader/view_model/reader_history_view_model.dart';
import 'package:wanandroid_flutter/src/model/reading_history_entry.dart';

void main() {
  test('reader history view model reports repository write failure', () async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        readingHistoryRepositoryProvider.overrideWithValue(
          _FailingHistoryRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final bool recorded = await container
        .read(readerHistoryViewModelProvider)
        .record(url: 'https://example.test/article', title: '固定文章');

    expect(recorded, isFalse);
  });
}

final class _FailingHistoryRepository implements ReadingHistoryRepository {
  @override
  Stream<int> get changes => const Stream<int>.empty();

  @override
  Future<void> clear() async {}

  @override
  Future<void> delete(String url) async {}

  @override
  Future<List<ReadingHistoryEntry>> page({
    int offset = 0,
    int limit = 20,
  }) async => const <ReadingHistoryEntry>[];

  @override
  Future<void> record({
    required String url,
    required String title,
    int? articleId,
  }) async {
    throw StateError('fixture write failure');
  }
}
