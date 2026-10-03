import 'package:wanandroid_flutter/src/model/article.dart';

/// 可收藏目标的身份。站内文章按 origin id 操作;
/// 列表记录按其 record id 操作;外部链接只会被取消收藏。
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

/// 服务端已知的收藏状态;未知(`collected == null`)时按契约
/// 必须先核对才能执行任何后续写入。
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

  /// 当前会话未认证时为 null。
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
