import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/model/search_history.dart';

abstract interface class SearchSuggestionsRepository {
  Future<SearchHistory> loadHistory();

  Future<DataResult<List<String>>> hotKeys(RequestCancellation cancellation);

  Future<bool> record(String keyword);

  Future<bool> clearHistory();
}
