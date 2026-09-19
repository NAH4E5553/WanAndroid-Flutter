// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reading_history_database.dart';

// ignore_for_file: type=lint
class $ReadingHistoryRowsTable extends ReadingHistoryRows
    with TableInfo<$ReadingHistoryRowsTable, ReadingHistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingHistoryRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _articleIdMeta = const VerificationMeta(
    'articleId',
  );
  @override
  late final GeneratedColumn<int> articleId = GeneratedColumn<int>(
    'article_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastReadAtMicrosMeta = const VerificationMeta(
    'lastReadAtMicros',
  );
  @override
  late final GeneratedColumn<int> lastReadAtMicros = GeneratedColumn<int>(
    'last_read_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    url,
    title,
    articleId,
    lastReadAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_history_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingHistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('article_id')) {
      context.handle(
        _articleIdMeta,
        articleId.isAcceptableOrUnknown(data['article_id']!, _articleIdMeta),
      );
    }
    if (data.containsKey('last_read_at_micros')) {
      context.handle(
        _lastReadAtMicrosMeta,
        lastReadAtMicros.isAcceptableOrUnknown(
          data['last_read_at_micros']!,
          _lastReadAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastReadAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {url};
  @override
  ReadingHistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingHistoryRow(
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      articleId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}article_id'],
      ),
      lastReadAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_read_at_micros'],
      )!,
    );
  }

  @override
  $ReadingHistoryRowsTable createAlias(String alias) {
    return $ReadingHistoryRowsTable(attachedDatabase, alias);
  }
}

class ReadingHistoryRow extends DataClass
    implements Insertable<ReadingHistoryRow> {
  final String url;
  final String title;
  final int? articleId;
  final int lastReadAtMicros;
  const ReadingHistoryRow({
    required this.url,
    required this.title,
    this.articleId,
    required this.lastReadAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['url'] = Variable<String>(url);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || articleId != null) {
      map['article_id'] = Variable<int>(articleId);
    }
    map['last_read_at_micros'] = Variable<int>(lastReadAtMicros);
    return map;
  }

  ReadingHistoryRowsCompanion toCompanion(bool nullToAbsent) {
    return ReadingHistoryRowsCompanion(
      url: Value(url),
      title: Value(title),
      articleId: articleId == null && nullToAbsent
          ? const Value.absent()
          : Value(articleId),
      lastReadAtMicros: Value(lastReadAtMicros),
    );
  }

  factory ReadingHistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingHistoryRow(
      url: serializer.fromJson<String>(json['url']),
      title: serializer.fromJson<String>(json['title']),
      articleId: serializer.fromJson<int?>(json['articleId']),
      lastReadAtMicros: serializer.fromJson<int>(json['lastReadAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'url': serializer.toJson<String>(url),
      'title': serializer.toJson<String>(title),
      'articleId': serializer.toJson<int?>(articleId),
      'lastReadAtMicros': serializer.toJson<int>(lastReadAtMicros),
    };
  }

  ReadingHistoryRow copyWith({
    String? url,
    String? title,
    Value<int?> articleId = const Value.absent(),
    int? lastReadAtMicros,
  }) => ReadingHistoryRow(
    url: url ?? this.url,
    title: title ?? this.title,
    articleId: articleId.present ? articleId.value : this.articleId,
    lastReadAtMicros: lastReadAtMicros ?? this.lastReadAtMicros,
  );
  ReadingHistoryRow copyWithCompanion(ReadingHistoryRowsCompanion data) {
    return ReadingHistoryRow(
      url: data.url.present ? data.url.value : this.url,
      title: data.title.present ? data.title.value : this.title,
      articleId: data.articleId.present ? data.articleId.value : this.articleId,
      lastReadAtMicros: data.lastReadAtMicros.present
          ? data.lastReadAtMicros.value
          : this.lastReadAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingHistoryRow(')
          ..write('url: $url, ')
          ..write('title: $title, ')
          ..write('articleId: $articleId, ')
          ..write('lastReadAtMicros: $lastReadAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(url, title, articleId, lastReadAtMicros);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingHistoryRow &&
          other.url == this.url &&
          other.title == this.title &&
          other.articleId == this.articleId &&
          other.lastReadAtMicros == this.lastReadAtMicros);
}

class ReadingHistoryRowsCompanion extends UpdateCompanion<ReadingHistoryRow> {
  final Value<String> url;
  final Value<String> title;
  final Value<int?> articleId;
  final Value<int> lastReadAtMicros;
  final Value<int> rowid;
  const ReadingHistoryRowsCompanion({
    this.url = const Value.absent(),
    this.title = const Value.absent(),
    this.articleId = const Value.absent(),
    this.lastReadAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadingHistoryRowsCompanion.insert({
    required String url,
    required String title,
    this.articleId = const Value.absent(),
    required int lastReadAtMicros,
    this.rowid = const Value.absent(),
  }) : url = Value(url),
       title = Value(title),
       lastReadAtMicros = Value(lastReadAtMicros);
  static Insertable<ReadingHistoryRow> custom({
    Expression<String>? url,
    Expression<String>? title,
    Expression<int>? articleId,
    Expression<int>? lastReadAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (url != null) 'url': url,
      if (title != null) 'title': title,
      if (articleId != null) 'article_id': articleId,
      if (lastReadAtMicros != null) 'last_read_at_micros': lastReadAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadingHistoryRowsCompanion copyWith({
    Value<String>? url,
    Value<String>? title,
    Value<int?>? articleId,
    Value<int>? lastReadAtMicros,
    Value<int>? rowid,
  }) {
    return ReadingHistoryRowsCompanion(
      url: url ?? this.url,
      title: title ?? this.title,
      articleId: articleId ?? this.articleId,
      lastReadAtMicros: lastReadAtMicros ?? this.lastReadAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (articleId.present) {
      map['article_id'] = Variable<int>(articleId.value);
    }
    if (lastReadAtMicros.present) {
      map['last_read_at_micros'] = Variable<int>(lastReadAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingHistoryRowsCompanion(')
          ..write('url: $url, ')
          ..write('title: $title, ')
          ..write('articleId: $articleId, ')
          ..write('lastReadAtMicros: $lastReadAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ReadingHistoryDatabase extends GeneratedDatabase {
  _$ReadingHistoryDatabase(QueryExecutor e) : super(e);
  $ReadingHistoryDatabaseManager get managers =>
      $ReadingHistoryDatabaseManager(this);
  late final $ReadingHistoryRowsTable readingHistoryRows =
      $ReadingHistoryRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [readingHistoryRows];
}

typedef $$ReadingHistoryRowsTableCreateCompanionBuilder =
    ReadingHistoryRowsCompanion Function({
      required String url,
      required String title,
      Value<int?> articleId,
      required int lastReadAtMicros,
      Value<int> rowid,
    });
typedef $$ReadingHistoryRowsTableUpdateCompanionBuilder =
    ReadingHistoryRowsCompanion Function({
      Value<String> url,
      Value<String> title,
      Value<int?> articleId,
      Value<int> lastReadAtMicros,
      Value<int> rowid,
    });

class $$ReadingHistoryRowsTableFilterComposer
    extends Composer<_$ReadingHistoryDatabase, $ReadingHistoryRowsTable> {
  $$ReadingHistoryRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get articleId => $composableBuilder(
    column: $table.articleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReadAtMicros => $composableBuilder(
    column: $table.lastReadAtMicros,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReadingHistoryRowsTableOrderingComposer
    extends Composer<_$ReadingHistoryDatabase, $ReadingHistoryRowsTable> {
  $$ReadingHistoryRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get articleId => $composableBuilder(
    column: $table.articleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReadAtMicros => $composableBuilder(
    column: $table.lastReadAtMicros,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReadingHistoryRowsTableAnnotationComposer
    extends Composer<_$ReadingHistoryDatabase, $ReadingHistoryRowsTable> {
  $$ReadingHistoryRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get articleId =>
      $composableBuilder(column: $table.articleId, builder: (column) => column);

  GeneratedColumn<int> get lastReadAtMicros => $composableBuilder(
    column: $table.lastReadAtMicros,
    builder: (column) => column,
  );
}

class $$ReadingHistoryRowsTableTableManager
    extends
        RootTableManager<
          _$ReadingHistoryDatabase,
          $ReadingHistoryRowsTable,
          ReadingHistoryRow,
          $$ReadingHistoryRowsTableFilterComposer,
          $$ReadingHistoryRowsTableOrderingComposer,
          $$ReadingHistoryRowsTableAnnotationComposer,
          $$ReadingHistoryRowsTableCreateCompanionBuilder,
          $$ReadingHistoryRowsTableUpdateCompanionBuilder,
          (
            ReadingHistoryRow,
            BaseReferences<
              _$ReadingHistoryDatabase,
              $ReadingHistoryRowsTable,
              ReadingHistoryRow
            >,
          ),
          ReadingHistoryRow,
          PrefetchHooks Function()
        > {
  $$ReadingHistoryRowsTableTableManager(
    _$ReadingHistoryDatabase db,
    $ReadingHistoryRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingHistoryRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadingHistoryRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReadingHistoryRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> url = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int?> articleId = const Value.absent(),
                Value<int> lastReadAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingHistoryRowsCompanion(
                url: url,
                title: title,
                articleId: articleId,
                lastReadAtMicros: lastReadAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String url,
                required String title,
                Value<int?> articleId = const Value.absent(),
                required int lastReadAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => ReadingHistoryRowsCompanion.insert(
                url: url,
                title: title,
                articleId: articleId,
                lastReadAtMicros: lastReadAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReadingHistoryRowsTable, ReadingHistoryRow>(
                    table,
                  ),
                  BaseReferences<
                    _$ReadingHistoryDatabase,
                    $ReadingHistoryRowsTable,
                    ReadingHistoryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReadingHistoryRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$ReadingHistoryDatabase,
      $ReadingHistoryRowsTable,
      ReadingHistoryRow,
      $$ReadingHistoryRowsTableFilterComposer,
      $$ReadingHistoryRowsTableOrderingComposer,
      $$ReadingHistoryRowsTableAnnotationComposer,
      $$ReadingHistoryRowsTableCreateCompanionBuilder,
      $$ReadingHistoryRowsTableUpdateCompanionBuilder,
      (
        ReadingHistoryRow,
        BaseReferences<
          _$ReadingHistoryDatabase,
          $ReadingHistoryRowsTable,
          ReadingHistoryRow
        >,
      ),
      ReadingHistoryRow,
      PrefetchHooks Function()
    >;

class $ReadingHistoryDatabaseManager {
  final _$ReadingHistoryDatabase _db;
  $ReadingHistoryDatabaseManager(this._db);
  $$ReadingHistoryRowsTableTableManager get readingHistoryRows =>
      $$ReadingHistoryRowsTableTableManager(_db, _db.readingHistoryRows);
}
