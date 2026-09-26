import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/reader/reading_history_provider.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/reading_history_repository.dart';
import 'package:wanandroid_flutter/src/features/profile/view_model/reading_history_view_model.dart';
import 'package:wanandroid_flutter/src/model/reading_history_entry.dart';

void main() {
  test(
    'reading history view model owns load, delete and stream refresh',
    () async {
      final _HistoryFixture repository = _HistoryFixture();
      addTearDown(repository.dispose);
      final ProviderContainer container = ProviderContainer(
        overrides: [
          readingHistoryRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final ProviderSubscription<ReadingHistoryUiState> subscription = container
          .listen(
            readingHistoryViewModelProvider,
            (_, _) {},
            fireImmediately: true,
          );
      addTearDown(subscription.close);

      await pumpEventQueue();
      expect(subscription.read().entries.single.title, '固定历史');

      final bool deleted = await container
          .read(readingHistoryViewModelProvider.notifier)
          .delete('https://example.test/history');
      expect(deleted, isTrue);
      await pumpEventQueue();
      expect(subscription.read().entries, isEmpty);
    },
  );
}

final class _HistoryFixture implements ReadingHistoryRepository {
  final StreamController<int> _changes = StreamController<int>.broadcast();
  final List<ReadingHistoryEntry> _entries = <ReadingHistoryEntry>[
    ReadingHistoryEntry(
      url: 'https://example.test/history',
      title: '固定历史',
      lastReadAt: DateTime.utc(2026, 9, 26),
      articleId: 1,
    ),
  ];

  @override
  Stream<int> get changes => _changes.stream;

  @override
  Future<void> clear() async {
    _entries.clear();
    _changes.add(0);
  }

  @override
  Future<void> delete(String url) async {
    _entries.removeWhere((ReadingHistoryEntry entry) => entry.url == url);
    _changes.add(_entries.length);
  }

  @override
  Future<List<ReadingHistoryEntry>> page({
    int offset = 0,
    int limit = 20,
  }) async => _entries.skip(offset).take(limit).toList(growable: false);

  @override
  Future<void> record({
    required String url,
    required String title,
    int? articleId,
  }) async {}

  Future<void> dispose() => _changes.close();
}
