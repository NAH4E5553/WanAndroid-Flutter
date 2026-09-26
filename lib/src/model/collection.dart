import 'package:wanandroid_flutter/src/model/article.dart';

/// Identity of a collectable target. Internal articles act on the origin id;
/// list records act on their record id; external links only ever uncollect.
class CollectionTarget {
  const CollectionTarget(this.articleId, this.recordId);

  final int? articleId;
  final int? recordId;

  String get key => 'article:$articleId|record:$recordId';

  @override
  bool operator ==(Object other) =>
      other is CollectionTarget && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

class CollectionItem {
  const CollectionItem({required this.target, required this.article});

  final CollectionTarget target;
  final Article article;
}

/// Server-known collect state; unknown (`collected == null`) requires
/// reconciliation before any follow-up write per the contract.
class CollectionStatus {
  const CollectionStatus({this.collected, this.busy = false});

  final bool? collected;
  final bool busy;

  CollectionStatus copyWith({bool? collected, bool? busy}) => CollectionStatus(
    collected: collected ?? this.collected,
    busy: busy ?? this.busy,
  );
}

class CollectionSnapshot {
  const CollectionSnapshot({
    this.generation,
    this.sessionKey,
    this.revision = 0,
    this.statuses = const <String, CollectionStatus>{},
  });

  /// Null when the current session is not authenticated.
  final int? generation;
  final String? sessionKey;
  final int revision;
  final Map<String, CollectionStatus> statuses;

  CollectionStatus status(CollectionTarget target) =>
      statuses[target.key] ?? const CollectionStatus();

  CollectionSnapshot copyWith({
    int? generation,
    String? sessionKey,
    int? revision,
    Map<String, CollectionStatus>? statuses,
  }) => CollectionSnapshot(
    generation: generation ?? this.generation,
    sessionKey: sessionKey ?? this.sessionKey,
    revision: revision ?? this.revision,
    statuses: statuses ?? this.statuses,
  );

  @override
  bool operator ==(Object other) =>
      other is CollectionSnapshot &&
      other.generation == generation &&
      other.sessionKey == sessionKey &&
      other.revision == revision &&
      other.statuses.length == statuses.length &&
      other.statuses.entries.every(
        (MapEntry<String, CollectionStatus> entry) =>
            statuses[entry.key]?.collected == entry.value.collected &&
            statuses[entry.key]?.busy == entry.value.busy,
      );

  @override
  int get hashCode => Object.hash(generation, sessionKey, revision);
}
