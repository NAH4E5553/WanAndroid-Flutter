import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/reader/reading_history_provider.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/data/database/reading_history_database.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_reading_history_repository.dart';
import 'package:wanandroid_flutter/src/features/profile/view/reading_history_screen.dart';

void main() {
  testWidgets('history opens a URL, reveals delete and confirms clear', (
    tester,
  ) async {
    final database = ReadingHistoryDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DefaultReadingHistoryRepository(database);
    await repository.record(
      url: 'https://example.test/first',
      title: '第一篇',
      articleId: 1,
    );
    await repository.record(
      url: 'https://example.test/second',
      title: '第二篇',
      articleId: 2,
    );
    String? opened;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readingHistoryRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: wanTheme(brightness: Brightness.light),
          home: ReadingHistoryScreen(
            onBack: () {},
            onPopped: () {},
            onRead: (url, title, articleId) => opened = url,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第一篇'), findsOneWidget);
    expect(find.text('第二篇'), findsOneWidget);
    expect(find.byTooltip('删除历史'), findsNothing);
    _expectMatchingRowHeight(tester, '第二篇', revealed: false);
    await tester.tap(find.text('第二篇'));
    expect(opened, 'https://example.test/second');

    await tester.drag(find.text('第二篇'), const Offset(-180, 0));
    await tester.pumpAndSettle();
    _expectMatchingRowHeight(tester, '第二篇', revealed: true);
    expect(find.byTooltip('删除历史'), findsOneWidget);
    await tester.tap(find.byTooltip('删除历史'));
    await tester.pumpAndSettle();
    expect(find.text('第二篇'), findsNothing);
    await tester.tap(find.byTooltip('清空历史'));
    await tester.pumpAndSettle();
    expect(find.text('清空阅读历史？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('第一篇'), findsOneWidget);
    await tester.tap(find.byTooltip('清空历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空').last);
    await tester.pumpAndSettle();
    expect(find.text('暂无阅读历史'), findsOneWidget);
  });

  testWidgets(
    'delete background follows text height in light, dark and large text',
    (tester) async {
      final database = ReadingHistoryDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = DefaultReadingHistoryRepository(database);
      await repository.record(
        url: 'https://example.test/long',
        title: '一个用于验证阅读历史长标题与删除操作等高的固定测试标题',
        articleId: 3,
      );

      for (final brightness in <Brightness>[
        Brightness.light,
        Brightness.dark,
      ]) {
        for (final textScale in <double>[1, 2]) {
          await tester.pumpWidget(
            ProviderScope(
              key: UniqueKey(),
              overrides: [
                readingHistoryRepositoryProvider.overrideWithValue(repository),
              ],
              child: MaterialApp(
                theme: wanTheme(brightness: brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
                home: ReadingHistoryScreen(
                  onBack: () {},
                  onPopped: () {},
                  onRead: (_, _, _) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          const title = '一个用于验证阅读历史长标题与删除操作等高的固定测试标题';
          _expectMatchingRowHeight(tester, title, revealed: false);
          await tester.drag(find.text(title), const Offset(-180, 0));
          await tester.pumpAndSettle();
          _expectMatchingRowHeight(tester, title, revealed: true);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}

void _expectMatchingRowHeight(
  WidgetTester tester,
  String title, {
  required bool revealed,
}) {
  final row = find
      .ancestor(of: find.text(title), matching: find.byType(ClipRRect))
      .first;
  final foreground = find
      .ancestor(of: find.text(title), matching: find.byType(Material))
      .first;
  final theme = Theme.of(tester.element(foreground));
  final foregroundMaterial = tester.widget<Material>(foreground);
  expect(foregroundMaterial.color, theme.cardTheme.color);
  expect(foregroundMaterial.borderRadius, BorderRadius.circular(12));
  expect(foregroundMaterial.clipBehavior, Clip.antiAlias);
  final action = find
      .descendant(of: row, matching: find.byType(ColoredBox))
      .first;
  final actionClip = find
      .ancestor(of: action, matching: find.byType(ClipRRect))
      .first;
  expect(
    tester.widget<ClipRRect>(actionClip).borderRadius,
    BorderRadius.circular(12),
  );
  final rowRect = tester.getRect(row);
  final foregroundRect = tester.getRect(foreground);
  final actionRect = tester.getRect(action);
  expect(actionRect.top, closeTo(rowRect.top, 0.01));
  expect(actionRect.bottom, closeTo(rowRect.bottom, 0.01));
  expect(foregroundRect.top, closeTo(rowRect.top, 0.01));
  expect(foregroundRect.bottom, closeTo(rowRect.bottom, 0.01));
  expect(foregroundRect.width, closeTo(rowRect.width, 0.01));
  expect(
    foregroundRect.right,
    closeTo(rowRect.right - (revealed ? 72 : 0), 0.01),
  );
}
