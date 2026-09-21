import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/collection.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

/// Account-scoped authority for collect state. No background scope, queued
/// writes, or optimistic success; every rule below mirrors the frozen
/// collection contract.
abstract interface class CollectionRepository {
  /// Observable snapshot; listeners fire on state transitions only.
  CollectionSnapshot get current;

  void addListener(void Function() listener);

  void removeListener(void Function() listener);

  /// Wraps a public article-list load: captures session and write version
  /// before the load, merges only eligible server hints afterwards, and
  /// annotates items with the session key when their state is known.
  Future<DataResult<PageResult<Article>>> articlePage(
    Future<DataResult<PageResult<Article>>> Function() load,
  );

  /// Loads one page of the signed-in account's collection list.
  Future<DataResult<PageResult<CollectionItem>>> page(int generation, int page);

  /// Read-only reconciliation for an unknown state: found only after reaching
  /// the list end; a bounded or failed scan stays unknown.
  Future<DataResult<void>> reconcile(int generation, CollectionTarget target);

  /// Drives the user's expressed goal, never a blind toggle of the latest
  /// known boolean.
  Future<DataResult<void>> setCollected(
    int generation,
    CollectionTarget target,
    bool collected,
  );
}
