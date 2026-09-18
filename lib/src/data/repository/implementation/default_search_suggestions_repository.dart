import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/mapper/wan_response_mapper.dart';
import 'package:wanandroid_flutter/src/data/network/article_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/network/dto/search_hot_key_dto.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/search_suggestions_repository.dart';
import 'package:wanandroid_flutter/src/data/storage/search_history_storage.dart';
import 'package:wanandroid_flutter/src/model/search_history.dart';

final class DefaultSearchSuggestionsRepository
    implements SearchSuggestionsRepository {
  DefaultSearchSuggestionsRepository(this._storage, this._network);

  static const int maxLength = 200;
  static const int maxItems = 20;

  final SearchHistoryStorage _storage;
  final ArticleNetworkDataSource _network;

  Future<void> _writeTail = Future<void>.value();

  @override
  Future<SearchHistory> loadHistory() async {
    try {
      await _writeTail;
      final List<String> values = await _storage.read();
      return SearchHistory(items: _normalize(values), ready: true);
    } catch (_) {
      return const SearchHistory(ready: true, readFailed: true);
    }
  }

  @override
  Future<DataResult<List<String>>> hotKeys(RequestCancellation cancellation) =>
      requestWithData<List<String>>(
        request: () => _network.hotKeys(cancellation),
        cancellation: cancellation,
        decode: (Object? data) {
          if (data is! List) {
            throw const FormatException('Hot keys must be a list.');
          }
          final List<SearchHotKeyDto> keys =
              data
                  .map((Object? item) {
                    if (item is! Map<String, dynamic>) {
                      throw const FormatException('Hot key must be an object.');
                    }
                    return SearchHotKeyDto.fromJson(item);
                  })
                  .toList(growable: false)
                ..sort(
                  (SearchHotKeyDto left, SearchHotKeyDto right) =>
                      left.order.compareTo(right.order),
                );
          return _normalize(keys.map((SearchHotKeyDto key) => key.name));
        },
      );

  @override
  Future<bool> record(String keyword) => _enqueue(() async {
    final String normalized = _take(keyword.trim());
    if (normalized.isEmpty) {
      return;
    }
    final List<String> current = await _storage.read();
    await _storage.write(_normalize(<String>[normalized, ...current]));
  });

  @override
  Future<bool> clearHistory() =>
      _enqueue(() => _storage.write(const <String>[]));

  Future<bool> _enqueue(Future<void> Function() operation) {
    final Future<void> next = _writeTail.then((_) => operation());
    _writeTail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next.then((_) => true, onError: (Object _) => false);
  }

  List<String> _normalize(Iterable<String> values) {
    final Map<String, String> unique = <String, String>{};
    for (final String raw in values) {
      final String value = _take(raw.trim());
      if (value.isNotEmpty) {
        unique.putIfAbsent(value, () => value);
      }
      if (unique.length == maxItems) {
        break;
      }
    }
    return unique.values.toList(growable: false);
  }

  String _take(String value) =>
      value.length <= maxLength ? value : value.substring(0, maxLength);
}
