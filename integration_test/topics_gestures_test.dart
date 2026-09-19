import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wanandroid_flutter/src/core/platform/app_visibility.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/features/topics/view/topics_screen.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_dependencies.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_view_model.dart';

import '../test/support/fixed_topic_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTopicsGestureTests();
}

void registerTopicsGestureTests() {
  testWidgets('horizontal, vertical, reversal and edge drags stay isolated', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        topicRepositoryProvider.overrideWithValue(
          const FixedTopicRepository(articlesPerPage: 30),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(appVisibilityProvider.notifier)
        .updateRoute(
          activeBranch: 1,
          homeRouteCurrent: false,
          topicsRouteCurrent: true,
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: wanTheme(brightness: Brightness.light),
          home: Scaffold(body: TopicsScreen(onArticleTap: (_) {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('专题文章 11'), findsOneWidget);

    final Finder pager = find.byKey(const ValueKey<String>('topic-pager'));
    final TestGesture reversed = await tester.startGesture(
      tester.getCenter(pager),
    );
    await reversed.moveBy(const Offset(-100, 0));
    await tester.pump(const Duration(milliseconds: 80));
    await reversed.moveBy(const Offset(100, 0));
    await reversed.up();
    await tester.pumpAndSettle();
    expect(find.text('专题文章 11'), findsOneWidget);
    expect(container.read(topicsViewModelProvider).selectedId, 11);

    await tester.drag(pager, const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(container.read(topicsViewModelProvider).selectedId, 11);
    expect(find.text('专题文章 11'), findsNothing);

    await tester.drag(pager, const Offset(-450, 0));
    await tester.pumpAndSettle();
    expect(container.read(topicsViewModelProvider).selectedId, 12);
    expect(find.text('专题文章 12'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('topic-menu-slot')))
          .width,
      0,
    );

    final Rect pagerBounds = tester.getRect(pager);
    final TestGesture edgeReturn = await tester.startGesture(
      Offset(pagerBounds.left + 5, pagerBounds.center.dy),
    );
    await edgeReturn.moveBy(const Offset(450, 0));
    await edgeReturn.up();
    await tester.pumpAndSettle();
    expect(pager, findsOneWidget);
    expect(container.read(topicsViewModelProvider).selectedId, 12);

    await tester.drag(pager, const Offset(450, 0));
    await tester.pumpAndSettle();
    expect(container.read(topicsViewModelProvider).selectedId, 11);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('topic-menu-slot')))
          .width,
      92,
    );
    expect(find.text('专题文章 11'), findsNothing);
  });
}
