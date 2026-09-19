import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:wanandroid_flutter/src/core/reader/reader_url_policy.dart';
import 'package:wanandroid_flutter/src/data/database/reading_history_database.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/reading_history_repository.dart';
import 'package:wanandroid_flutter/src/model/reading_history_entry.dart';

class DefaultReadingHistoryRepository implements ReadingHistoryRepository {
  DefaultReadingHistoryRepository(
    this._db, {
    this.allowLoopbackFixture = false,
  });

  final ReadingHistoryDatabase _db;
  final bool allowLoopbackFixture;
  final StreamController<int> _changes = StreamController<int>.broadcast();
  Future<void> _tail = Future<void>.value();
  int _version = 0;

  @override
  Stream<int> get changes => _changes.stream;

  Future<T> _ordered<T>(Future<T> Function() action) {
    final Completer<T> completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  @override
  Future<List<ReadingHistoryEntry>> page({int offset = 0, int limit = 20}) =>
      _ordered(() async {
        if (offset < 0 || limit < 1 || limit > 100) {
          throw ArgumentError('Invalid history page');
        }
        final rows =
            await (_db.select(_db.readingHistoryRows)
                  ..orderBy([
                    (row) => OrderingTerm(
                      expression: row.lastReadAtMicros,
                      mode: OrderingMode.desc,
                    ),
                    (row) => OrderingTerm(expression: row.url),
                  ])
                  ..limit(limit, offset: offset))
                .get();
        return [
          for (final row in rows)
            ReadingHistoryEntry(
              url: row.url,
              title: row.title,
              lastReadAt: DateTime.fromMicrosecondsSinceEpoch(
                row.lastReadAtMicros,
                isUtc: true,
              ),
              articleId: row.articleId,
            ),
        ];
      });

  @override
  Future<void> record({
    required String url,
    required String title,
    int? articleId,
  }) => _ordered(() async {
    final Uri? canonical = ReaderUrlPolicy.canonicalHistoryUrl(
      url,
      allowLoopbackFixture: allowLoopbackFixture,
    );
    if (canonical == null) throw const FormatException('Invalid history URL');
    final String trimmedTitle = title.trim();
    final latest =
        await (_db.select(_db.readingHistoryRows)
              ..orderBy([
                (row) => OrderingTerm(
                  expression: row.lastReadAtMicros,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();
    final int lastReadAtMicros = max(
      DateTime.now().toUtc().microsecondsSinceEpoch,
      (latest?.lastReadAtMicros ?? 0) + 1,
    );
    await _db
        .into(_db.readingHistoryRows)
        .insertOnConflictUpdate(
          ReadingHistoryRowsCompanion.insert(
            url: canonical.toString(),
            title: trimmedTitle.isEmpty
                ? canonical.toString()
                : trimmedTitle.substring(0, trimmedTitle.length.clamp(0, 200)),
            articleId: Value(
              articleId != null && articleId >= 0 ? articleId : null,
            ),
            lastReadAtMicros: lastReadAtMicros,
          ),
        );
    _changes.add(++_version);
  });

  @override
  Future<void> delete(String url) => _ordered(() async {
    final Uri? canonical = ReaderUrlPolicy.canonicalHistoryUrl(
      url,
      allowLoopbackFixture: allowLoopbackFixture,
    );
    if (canonical == null) return;
    await (_db.delete(
      _db.readingHistoryRows,
    )..where((row) => row.url.equals(canonical.toString()))).go();
    _changes.add(++_version);
  });

  @override
  Future<void> clear() => _ordered(() async {
    await _db.delete(_db.readingHistoryRows).go();
    _changes.add(++_version);
  });
}
