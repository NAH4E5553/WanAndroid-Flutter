import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/data/network/article_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_search_suggestions_repository.dart';
import 'package:wanandroid_flutter/src/data/storage/search_history_storage.dart';

void main() {
  test('normalizes, deduplicates, truncates and caps search history', () async {
    final _MemoryStorage storage = _MemoryStorage(<String>[
      ' old ',
      'old',
      '',
      ...List<String>.generate(25, (int index) => 'item-$index'),
    ]);
    final DefaultSearchSuggestionsRepository repository =
        DefaultSearchSuggestionsRepository(storage, _UnusedNetwork());

    final history = await repository.loadHistory();

    expect(history.ready, isTrue);
    expect(history.items.first, 'old');
    expect(history.items.length, 20);

    final String longKeyword = List<String>.filled(210, '字').join();
    expect(await repository.record(longKeyword), isTrue);
    expect(storage.values.first.length, 200);
    expect(storage.values.length, 20);
  });

  test('serializes record and clear so invocation order wins', () async {
    final _BlockingStorage storage = _BlockingStorage();
    final DefaultSearchSuggestionsRepository repository =
        DefaultSearchSuggestionsRepository(storage, _UnusedNetwork());

    final Future<bool> record = repository.record('first');
    final Future<bool> clear = repository.clearHistory();
    await Future<void>.delayed(Duration.zero);
    expect(storage.writeCalls, 1);

    storage.releaseNextWrite();
    expect(await record, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(storage.writeCalls, 2);
    storage.releaseNextWrite();

    expect(await clear, isTrue);
    expect(storage.values, isEmpty);
  });

  test('reports read and write failures without replacing history', () async {
    final _MemoryStorage storage = _MemoryStorage(<String>['kept']);
    final DefaultSearchSuggestionsRepository repository =
        DefaultSearchSuggestionsRepository(storage, _UnusedNetwork());
    storage.failWrites = true;

    expect(await repository.clearHistory(), isFalse);
    expect((await repository.loadHistory()).items, <String>['kept']);

    storage.failReads = true;
    final history = await repository.loadHistory();
    expect(history.ready, isTrue);
    expect(history.readFailed, isTrue);
  });
}

class _MemoryStorage implements SearchHistoryStorage {
  _MemoryStorage(List<String> initial) : values = List<String>.of(initial);

  List<String> values;
  bool failReads = false;
  bool failWrites = false;

  @override
  Future<List<String>> read() async {
    if (failReads) throw StateError('fixture read failure');
    return List<String>.of(values);
  }

  @override
  Future<void> write(List<String> values) async {
    if (failWrites) throw StateError('fixture write failure');
    this.values = List<String>.of(values);
  }
}

class _BlockingStorage extends _MemoryStorage {
  _BlockingStorage() : super(<String>[]);

  final List<Completer<void>> _writes = <Completer<void>>[];

  int get writeCalls => _writes.length;

  @override
  Future<void> write(List<String> values) async {
    final Completer<void> completer = Completer<void>();
    _writes.add(completer);
    await completer.future;
    this.values = List<String>.of(values);
  }

  void releaseNextWrite() {
    _writes.firstWhere((Completer<void> item) => !item.isCompleted).complete();
  }
}

class _UnusedNetwork implements ArticleNetworkDataSource {
  Never _unused() => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> articles(
    int page,
    RequestCancellation cancellation,
  ) => _unused();

  @override
  Future<Map<String, dynamic>> hotKeys(RequestCancellation cancellation) =>
      _unused();

  @override
  Future<Map<String, dynamic>> questions(
    int page,
    RequestCancellation cancellation,
  ) => _unused();

  @override
  Future<Map<String, dynamic>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) => _unused();
}
