import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'reading_history_database.g.dart';

class ReadingHistoryRows extends Table {
  TextColumn get url => text()();
  TextColumn get title => text()();
  IntColumn get articleId => integer().nullable()();
  IntColumn get lastReadAtMicros => integer()();

  @override
  Set<Column<Object>> get primaryKey => {url};
}

@DriftDatabase(tables: [ReadingHistoryRows])
class ReadingHistoryDatabase extends _$ReadingHistoryDatabase {
  ReadingHistoryDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'reading_history'));

  @override
  int get schemaVersion => 1;
}
