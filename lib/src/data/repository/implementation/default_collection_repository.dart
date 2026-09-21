import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/mapper/wan_response_mapper.dart';
import 'package:wanandroid_flutter/src/data/network/collection_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_models.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_store.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/collection_repository.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/collection.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

final class DefaultCollectionRepository implements CollectionRepository {
  DefaultCollectionRepository({
    required this._source,
    required this._sessions,
    this.reconcileTimeout = const Duration(seconds: 30),
    this.maxReconcilePages = 50,
  }) {
    _sessions.addListener(_onSessionChanged);
    // Sync with a session that may already be authenticated at construction.
    _onSessionChanged();
  }

  final CollectionNetworkDataSource _source;
  final SessionStore _sessions;
  final Duration reconcileTimeout;
  final int maxReconcilePages;

  CollectionSnapshot _snapshot = const CollectionSnapshot();
  int _writeVersion = 0;
  final Set<VoidCallback> _listeners = <VoidCallback>{};

  @override
  CollectionSnapshot get current => _snapshot;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notify() {
    for (final VoidCallback listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  /// Account switches replace the snapshot; same-account state changes only
  /// matter to listeners that also observe the session store.
  void _onSessionChanged() {
    final SessionSnapshot session = _sessions.snapshot;
    final int? generation = session.authenticated ? session.generation : null;
    if (_snapshot.generation != generation) {
      _snapshot = CollectionSnapshot(
        generation: generation,
        sessionKey: generation == null
            ? null
            : _sessions.authenticatedVersionKey(),
      );
      _notify();
    }
  }

  @override
  Future<DataResult<PageResult<Article>>> articlePage(
    Future<DataResult<PageResult<Article>>> Function() load,
  ) async {
    final SessionRequest tag = _sessions.capture();
    final int version = _writeVersion;
    final DataResult<PageResult<Article>> result = await load();
    if (result is DataFailure<PageResult<Article>>) {
      return result;
    }
    final PageResult<Article> page =
        (result as DataSuccess<PageResult<Article>>).value;
    if (!_sessions.isCurrent(tag)) {
      return const DataFailure<PageResult<Article>>(DataError.sessionChanged);
    }
    final CollectionSnapshot old = _snapshot;
    // Re-verification may complete while reading without changing the account
    // generation; the write epoch decides whether hints are eligible.
    final bool accepted = old.generation != null && version == _writeVersion;
    final Map<String, CollectionStatus> updates = accepted
        ? <String, CollectionStatus>{
            for (final Article article in page.items)
              if (!(old.status(CollectionTarget(article.id, null)).busy))
                CollectionTarget(article.id, null).key: CollectionStatus(
                  collected: article.collected,
                ),
          }
        : const <String, CollectionStatus>{};
    _snapshot = old.copyWith(statuses: {...old.statuses, ...updates});
    return DataSuccess<PageResult<Article>>(
      PageResult<Article>(
        items: page.items
            .map((Article article) {
              final bool? known = _snapshot
                  .status(CollectionTarget(article.id, null))
                  .collected;
              return Article(
                id: article.id,
                title: article.title,
                url: article.url,
                author: article.author,
                shareUser: article.shareUser,
                superChapterName: article.superChapterName,
                chapter: article.chapter,
                publishedAt: article.publishedAt,
                collected: known ?? article.collected,
                // Unknown or invalidated results cannot seed a later reader.
                collectionSession: known != null ? old.sessionKey : null,
              );
            })
            .toList(growable: false),
        nextPage: page.nextPage,
      ),
    );
  }

  SessionRequest? _request(int generation) {
    final SessionRequest tag = _sessions.capture();
    if (tag.generation != generation || _snapshot.generation != generation) {
      return null;
    }
    return tag;
  }

  DataFailure<T> _changed<T>() => DataFailure<T>(DataError.sessionChanged);

  void _publish(
    SessionRequest tag,
    CollectionTarget target,
    CollectionStatus status, {
    bool changed = false,
  }) {
    final CollectionSnapshot old = _snapshot;
    // Validate the exact snapshot being copied, never resample another
    // account afterwards.
    if (old.generation == tag.generation) {
      _snapshot = old.copyWith(
        statuses: {...old.statuses, target.key: status},
        revision: old.revision + (changed ? 1 : 0),
      );
      _notify();
    }
  }

  bool _begin(SessionRequest tag, CollectionTarget target) {
    final CollectionSnapshot old = _snapshot;
    if (old.generation != tag.generation || old.status(target).busy) {
      return false;
    }
    _snapshot = old.copyWith(
      statuses: {
        ...old.statuses,
        target.key: old.status(target).copyWith(busy: true),
      },
    );
    _notify();
    return true;
  }

  CollectionStatus _statusOf(CollectionTarget target) =>
      _snapshot.status(target);

  @override
  Future<DataResult<PageResult<CollectionItem>>> page(
    int generation,
    int page,
  ) async {
    final SessionRequest? tag = _request(generation);
    if (tag == null) {
      return _changed();
    }
    final int revision = _writeVersion;
    final DataResult<PageResult<CollectionItem>> result = await _readPage(
      tag,
      page,
    );
    final CollectionSnapshot old = _snapshot;
    if (old.generation != tag.generation || _writeVersion != revision) {
      return _changed();
    }
    if (result is DataSuccess<PageResult<CollectionItem>>) {
      final Map<String, CollectionStatus> known = <String, CollectionStatus>{
        for (final CollectionItem item in result.value.items.where(
          (CollectionItem item) => !old.status(item.target).busy,
        ))
          item.target.key: const CollectionStatus(collected: true),
      };
      _snapshot = old.copyWith(statuses: {...old.statuses, ...known});
      _notify();
    }
    return result;
  }

  Future<DataResult<PageResult<CollectionItem>>> _readPage(
    SessionRequest tag,
    int page,
  ) async {
    final DataResult<PageResult<CollectionItem>> result =
        await requestWithData<PageResult<CollectionItem>>(
          request: () => _source.list(page, tag),
          decode: (Object? data) => _decodePage(data, tag, page),
          cancellation: const LiveRequestCancellation(),
        );
    return _sessions.isCurrent(tag) ? result : _changed();
  }

  /// Strips the fragment and guarantees a non-empty path, matching the
  /// collection-entry link normalization the Android version applies.
  static String _normalizeLink(String raw) {
    final Uri uri = Uri.parse(raw.split('#').first);
    final String normalized = uri.toString();
    if (uri.path.isNotEmpty) {
      return normalized;
    }
    final int query = normalized.indexOf('?');
    return Uri.parse(
      query < 0
          ? '$normalized/'
          : '${normalized.substring(0, query)}/${normalized.substring(query)}',
    ).toString();
  }

  PageResult<CollectionItem> _decodePage(
    Object? data,
    SessionRequest tag,
    int page,
  ) {
    if (data is! Map) {
      throw const FormatException();
    }
    final Object? datas = data['datas'];
    final Object? over = data['over'];
    if (datas is! List || over is! bool) {
      throw const FormatException();
    }
    final List<CollectionItem> items = datas
        .map((Object? raw) {
          if (raw is! Map) {
            throw const FormatException();
          }
          final Object? id = raw['id'];
          final Object? originId = raw['originId'];
          final Object? title = raw['title'];
          final Object? link = raw['link'];
          if (id is! int || title is! String || link is! String) {
            throw const FormatException();
          }
          final int recordId = id;
          final int articleId = originId is int && originId >= 0
              ? originId
              : -1;
          final CollectionTarget target = CollectionTarget(
            articleId >= 0 ? articleId : null,
            recordId,
          );
          return CollectionItem(
            target: target,
            article: Article(
              id: articleId >= 0 ? articleId : recordId,
              title: title,
              url: _normalizeLink(link),
              author: raw['author'] is String ? raw['author'] as String : '',
              shareUser: '',
              superChapterName: raw['chapterName'] is String
                  ? raw['chapterName'] as String
                  : '',
              chapter: '',
              publishedAt: raw['niceDate'] is String
                  ? raw['niceDate'] as String
                  : '',
              collected: true,
              collectionSession: _sessions.isCurrent(tag)
                  ? _sessions.authenticatedVersionKey()
                  : null,
            ),
          );
        })
        .toList(growable: false);
    return PageResult<CollectionItem>(
      items: items,
      nextPage: over ? null : page + 1,
    );
  }

  @override
  Future<DataResult<void>> reconcile(int generation, CollectionTarget target) {
    final SessionRequest? tag = _request(generation);
    if (tag == null) {
      return Future<DataResult<void>>.value(_changed());
    }
    if (!_begin(tag, target)) {
      return Future<DataResult<void>>.value(const DataSuccess<void>(null));
    }
    return _reconcileLocked(tag, target).whenComplete(() {
      _publish(tag, target, _statusOf(target).copyWith(busy: false));
    });
  }

  /// Absence is known only after reaching the end; a bounded/failed scan
  /// stays unknown.
  Future<DataResult<void>> _reconcileLocked(
    SessionRequest tag,
    CollectionTarget target,
  ) async {
    _publish(tag, target, const CollectionStatus(busy: true));
    final int version = _writeVersion;
    final DataResult<void> outcome = await _withTimeout(
      reconcileTimeout,
      () async {
        for (int page = 0; page < maxReconcilePages; page++) {
          final DataResult<PageResult<CollectionItem>> result = await _readPage(
            tag,
            page,
          );
          if (result is DataFailure<PageResult<CollectionItem>>) {
            return DataFailure<void>(result.error);
          }
          final PageResult<CollectionItem> value =
              (result as DataSuccess<PageResult<CollectionItem>>).value;
          final bool found = value.items.any(
            (CollectionItem item) => item.target.key == target.key,
          );
          if (found || value.nextPage == null) {
            if (!_sessions.isCurrent(tag) || _writeVersion != version) {
              return _changed();
            }
            _publish(
              tag,
              target,
              CollectionStatus(collected: found, busy: true),
            );
            return const DataSuccess<void>(null);
          }
        }
        return const DataFailure<void>(DataError.network);
      },
    );
    return outcome;
  }

  @override
  Future<DataResult<void>> setCollected(
    int generation,
    CollectionTarget target,
    bool collected,
  ) async {
    final SessionRequest? tag = _request(generation);
    if (tag == null) {
      return _changed();
    }
    if (!_begin(tag, target)) {
      return const DataSuccess<void>(null);
    }
    bool attempted = false;
    DataResult<void> result = const DataSuccess<void>(null);
    try {
      final bool? previous = _statusOf(target).collected;
      // An uncertain previous request can only be reconciled, never blindly
      // replayed.
      if (previous == null) {
        result = await _reconcileLocked(tag, target);
        return result;
      }
      if (previous == collected) {
        return const DataSuccess<void>(null);
      }
      if (collected && target.articleId == null) {
        return const DataFailure<void>(DataError.service);
      }
      attempted = true;
      _writeVersion++;
      _publish(tag, target, const CollectionStatus(busy: true));
      result = await requestWithoutData(
        request: () {
          if (collected) {
            return _source.collect(target.articleId!, tag);
          }
          if (target.recordId != null) {
            return _source.uncollectRecord(
              target.recordId!,
              target.articleId ?? -1,
              tag,
            );
          }
          return _source.uncollectArticle(target.articleId!, tag);
        },
        cancellation: const LiveRequestCancellation(),
      );
      if (!_sessions.isCurrent(tag)) {
        return _changed();
      }
      if (result is DataSuccess<void>) {
        _publish(
          tag,
          target,
          CollectionStatus(collected: collected, busy: true),
        );
      } else if (result is DataFailure<void> &&
          (result.error == DataError.network ||
              result.error == DataError.invalidResponse)) {
        // The server may have committed before the connection was lost:
        // reconcile the true state; the reported result stays the write's.
        await _reconcileLocked(tag, target);
      } else {
        _publish(
          tag,
          target,
          CollectionStatus(collected: previous, busy: true),
        );
      }
      if (!_sessions.isCurrent(tag)) {
        return _changed();
      }
      return _statusOf(target).collected == collected
          ? const DataSuccess<void>(null)
          : result;
    } finally {
      if (attempted) {
        _writeVersion++;
      }
      // Refresh pagination after every attempted write, including uncertain
      // writes.
      _publish(
        tag,
        target,
        _statusOf(target).copyWith(busy: false),
        changed: attempted,
      );
    }
  }

  Future<DataResult<void>> _withTimeout(
    Duration timeout,
    Future<DataResult<void>> Function() body,
  ) => body().timeout(
    timeout,
    onTimeout: () => Future<DataResult<void>>.value(
      const DataFailure<void>(DataError.network),
    ),
  );
}
