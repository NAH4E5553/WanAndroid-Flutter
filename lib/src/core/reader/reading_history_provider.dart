import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/reading_history_repository.dart';

/// 面向 reader/profile ViewModel 的组装 provider;View 绝不得直接读取
/// 仓储 provider。
final readingHistoryRepositoryProvider = Provider<ReadingHistoryRepository>(
  (ref) => throw StateError('Reading history repository is not configured'),
);
