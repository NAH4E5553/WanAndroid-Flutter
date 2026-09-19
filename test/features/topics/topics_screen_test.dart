import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/platform/app_visibility.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/features/topics/view/topics_screen.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_dependencies.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_view_model.dart';

import '../../support/fixed_topic_repository.dart';

void main() {
  testWidgets('click and horizontal swipe select real child IDs', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);
    await _pump(tester, container);

    expect(find.text('专题文章 11'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('topic-menu-slot')))
          .width,
      92,
    );
    await tester.tap(find.byKey(const ValueKey<String>('topic-tab-12')));
    await tester.pumpAndSettle();
    expect(find.text('专题文章 12'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('topic-menu-slot')))
          .width,
      0,
    );
    expect(find.textContaining('分类：'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey<String>('topic-pager')),
      const Offset(450, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('专题文章 11'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('topic-menu-slot')))
          .width,
      92,
    );
  });

  testWidgets('parent switch uses its own first child without an All tab', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);
    await _pump(tester, container);

    await tester.tap(find.byKey(const ValueKey<String>('topic-20')));
    await tester.pumpAndSettle();
    expect(find.text('专题文章 21'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('topic-tab-21')), findsOneWidget);
    expect(find.text('全部'), findsNothing);
  });

  testWidgets('dark mode and 200 percent text remain operable', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);
    await _pump(tester, container, dark: true, largeText: true);

    expect(find.byKey(const ValueKey<String>('topic-tab-11')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('topic-tab-12')));
    await tester.pumpAndSettle();
    expect(find.text('专题文章 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar fades mid-animation and reverses at fixed width', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = _container();
    addTearDown(container.dispose);
    await _pump(tester, container);

    container.read(topicsViewModelProvider.notifier).selectChild(10, 12);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final double width = tester
        .getSize(find.byKey(const ValueKey<String>('topic-menu-slot')))
        .width;
    final double opacity = tester
        .widget<Opacity>(find.byKey(const ValueKey<String>('topic-menu-fade')))
        .opacity;
    expect(width, inExclusiveRange(0, 92));
    expect(opacity, inExclusiveRange(0, 1));
    container.read(topicsViewModelProvider.notifier).selectChild(10, 11);
    await tester.pumpAndSettle();

    expect(find.text('专题文章 11'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('topic-menu-slot')))
          .width,
      92,
    );
    expect(tester.takeException(), isNull);
  });
}

ProviderContainer _container() {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      topicRepositoryProvider.overrideWithValue(const FixedTopicRepository()),
    ],
  );
  container
      .read(appVisibilityProvider.notifier)
      .updateRoute(
        activeBranch: 1,
        homeRouteCurrent: false,
        topicsRouteCurrent: true,
      );
  return container;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  bool dark = false,
  bool largeText = false,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        theme: wanTheme(brightness: Brightness.light),
        darkTheme: wanTheme(brightness: Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 800),
            textScaler: TextScaler.linear(largeText ? 2 : 1),
          ),
          child: Scaffold(body: TopicsScreen(onArticleTap: (_) {})),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
