import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/topic_repository.dart';

final Provider<TopicRepository> topicRepositoryProvider =
    Provider<TopicRepository>(
      (Ref ref) => throw StateError(
        'TopicRepository must be provided by the application bootstrap.',
      ),
    );
