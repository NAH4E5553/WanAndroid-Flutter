import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/data/database/reading_history_database.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_reading_history_repository.dart';

void main() {
  late ReadingHistoryDatabase database;
  late DefaultReadingHistoryRepository repository;

  setUp(() {
    database = ReadingHistoryDatabase(NativeDatabase.memory());
    repository = DefaultReadingHistoryRepository(database);
  });

  tearDown(() async => database.close());

  test(
    'fragment dedupes while distinct queries remain and article ID updates',
    () async {
      await repository.record(
        url: 'https://EXAMPLE.test:443/a?q=1#first',
        title: ' first ',
        articleId: 3,
      );
      await repository.record(
        url: 'https://example.test/a?q=1#second',
        title: 'second',
        articleId: null,
      );
      await repository.record(
        url: 'https://example.test/a?q=2',
        title: 'third',
        articleId: 4,
      );
      final rows = await repository.page();
      expect(rows.length, 2);
      expect(rows.first.url, 'https://example.test/a?q=2');
      expect(rows.first.lastReadAt.isAfter(rows.last.lastReadAt), isTrue);
      expect(
        rows.map((row) => row.url),
        containsAll([
          'https://example.test/a?q=1',
          'https://example.test/a?q=2',
        ]),
      );
      expect(
        rows.singleWhere((row) => row.url.endsWith('q=1')).articleId,
        isNull,
      );
      expect(
        rows.singleWhere((row) => row.url.endsWith('q=1')).title,
        'second',
      );
    },
  );

  test('serial writes, pagination, deletion and clear', () async {
    await Future.wait([
      for (var i = 0; i < 25; i++)
        repository.record(url: 'https://example.test/$i', title: '$i'),
    ]);
    expect((await repository.page()).length, 20);
    expect((await repository.page(offset: 20)).length, 5);
    await repository.delete('https://example.test/0#fragment');
    expect((await repository.page(limit: 100)).length, 24);
    await repository.clear();
    expect(await repository.page(), isEmpty);
  });

  test(
    'record and clear preserve call order and same-size update emits',
    () async {
      final versions = <int>[];
      final subscription = repository.changes.listen(versions.add);
      await Future.wait([
        repository.record(url: 'https://example.test/one', title: '一'),
        repository.clear(),
        repository.record(url: 'https://example.test/two', title: '二'),
      ]);
      final rows = await repository.page();
      expect(rows.map((row) => row.url), ['https://example.test/two']);
      await repository.record(url: 'https://example.test/two', title: '改名');
      expect((await repository.page()).single.title, '改名');
      expect(versions, [1, 2, 3, 4]);
      await subscription.cancel();
    },
  );

  test('invalid URL is not stored', () async {
    await expectLater(
      repository.record(url: 'http://example.test/a', title: 'unsafe'),
      throwsFormatException,
    );
    await expectLater(
      repository.record(url: 'javascript:alert(1)', title: 'unsafe'),
      throwsFormatException,
    );
    expect(await repository.page(), isEmpty);
  });

  test('reopening the database keeps history and schema version', () async {
    await database.close();
    final Directory directory = await Directory.systemTemp.createTemp(
      'wan-history-',
    );
    final File file = File('${directory.path}/reading.sqlite');
    try {
      final firstDatabase = ReadingHistoryDatabase(NativeDatabase(file));
      final firstRepository = DefaultReadingHistoryRepository(firstDatabase);
      await firstRepository.record(
        url: 'https://example.test/p#fragment',
        title: '持久化',
        articleId: 9,
      );
      await firstDatabase.close();
      final reopenedDatabase = ReadingHistoryDatabase(NativeDatabase(file));
      final reopenedRepository = DefaultReadingHistoryRepository(
        reopenedDatabase,
      );
      final rows = await reopenedRepository.page();
      expect(rows.single.url, 'https://example.test/p');
      expect(rows.single.articleId, 9);
      expect(rows.single.title, '持久化');
      await reopenedDatabase.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
