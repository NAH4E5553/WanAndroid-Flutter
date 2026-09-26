import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/reading_history_repository.dart';

/// Composition provider for reader/profile ViewModels; Views must not read the
/// repository provider directly.
final readingHistoryRepositoryProvider = Provider<ReadingHistoryRepository>(
  (ref) => throw StateError('Reading history repository is not configured'),
);
