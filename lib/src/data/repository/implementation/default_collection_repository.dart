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

  String? _canonicalKey(CollectionTarget target) {
    final int? articleId = target.articleId;
    return articleId == null ? null : CollectionTarget(articleId, null).key;
  }

  Set<String> _coordinatedKeys(
    CollectionSnapshot snapshot,
    CollectionTarget target,
  ) {
    final Set<String> keys = <String>{target.key};
    final int? articleId = target.articleId;
    if (articleId == null) return keys;
    keys.add(CollectionTarget(articleId, null).key);
    final String recordPrefix = 'article:$articleId|record:';
    keys.addAll(
      snapshot.statuses.keys.where(
        (String key) => key.startsWith(recordPrefix),
      ),
    );
    return keys;
  }

  bool _isBusy(CollectionSnapshot snapshot, CollectionTarget target) =>
      _coordinatedKeys(
        snapshot,
        target,
      ).any((String key) => snapshot.statuses[key]?.busy ?? false);

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
      final String? canonicalKey = _canonicalKey(target);
      final Map<String, CollectionStatus> statuses = <String, CollectionStatus>{
        ...old.statuses,
      };
      for (final String key in _coordinatedKeys(old, target)) {
        final CollectionStatus existing =
            old.statuses[key] ?? const CollectionStatus();
        final bool direct = key == target.key || key == canonicalKey;
        statuses[key] = CollectionStatus(
          // A confirmed uncollect applies to every known record alias for the
          // article. A collect only updates the requested/canonical identity:
          // a later collect can receive a new record id and must not revive a
          // tombstone for the old record.
          collected: direct || status.collected == false
              ? status.collected
              : existing.collected,
          busy: status.busy,
        );
      }
      _snapshot = old.copyWith(
        statuses: statuses,
        revision: old.revision + (changed ? 1 : 0),
      );
      _notify();
    }
  }

  bool _begin(SessionRequest tag, CollectionTarget target) {
    final CollectionSnapshot old = _snapshot;
    if (old.generation != tag.generation || _isBusy(old, target)) {
      return false;
    }
    final Map<String, CollectionStatus> statuses = <String, CollectionStatus>{
      ...old.statuses,
    };
    for (final String key in _coordinatedKeys(old, target)) {
      statuses[key] = (old.statuses[key] ?? const CollectionStatus()).copyWith(
        busy: true,
      );
    }
    _snapshot = old.copyWith(statuses: statuses);
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
      // A successful uncollect is newer than a collection-list response that
      // still contains the same server record. Keep that record hidden until
      // the server list catches up. A later re-collect receives a new record
      // id, so this tombstone cannot suppress the new collection.
      final List<CollectionItem> visibleItems = result.value.items
          .where(
            (CollectionItem item) => old.status(item.target).collected != false,
          )
          .toList(growable: false);
      final Map<String, CollectionStatus> known = <String, CollectionStatus>{
        ...old.statuses,
      };
      for (final CollectionItem item in visibleItems) {
        if (_isBusy(old, item.target)) continue;
        known[item.target.key] = const CollectionStatus(collected: true);
        final String? canonicalKey = _canonicalKey(item.target);
        if (canonicalKey != null) {
          known[canonicalKey] = const CollectionStatus(collected: true);
        }
      }
      _snapshot = old.copyWith(statuses: known);
      _notify();
      return DataSuccess<PageResult<CollectionItem>>(
        PageResult<CollectionItem>(
          items: visibleItems,
          nextPage: result.value.nextPage,
        ),
      );
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
            (CollectionItem item) => target.recordId != null
                ? item.target.key == target.key
                : item.target.articleId == target.articleId,
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
