import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/paging/paging_state.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/core/ui/network_list_page.dart';

void main() {
  testWidgets('renders initial loading, failure and empty states', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const PagedState<String>(initial: LoadLoading()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pump(
      tester,
      const PagedState<String>(initial: LoadFailure(DataError.invalidResponse)),
    );
    expect(find.text('数据格式异常，请稍后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await _pump(tester, const PagedState<String>());
    expect(find.text('固定空态'), findsOneWidget);
  });

  testWidgets('renders items and bounded paging footer states', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const PagedState<String>(
        items: <String>['one'],
        nextPage: 2,
        append: LoadFailure(DataError.network),
      ),
    );
    expect(find.text('one'), findsOneWidget);
    expect(find.text('加载失败，点击重试'), findsOneWidget);

    await _pump(
      tester,
      const PagedState<String>(
        items: <String>['one'],
        nextPage: 2,
        autoLoadPaused: true,
      ),
    );
    expect(find.text('继续加载'), findsOneWidget);

    await _pump(tester, const PagedState<String>(items: <String>['one']));
    expect(find.text('已经到底了'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, PagedState<String> state) =>
    tester.pumpWidget(
      MaterialApp(
        theme: wanTheme(brightness: Brightness.light),
        home: Scaffold(
          body: NetworkListPage<String>(
            state: state,
            emptyLabel: '固定空态',
            onRefresh: () async {},
            onRetryInitial: () {},
            onLoadMore: () {},
            onRetryLoadMore: () {},
            onContinue: () {},
            itemBuilder: (BuildContext context, String item, int index) =>
                Text(item),
          ),
        ),
      ),
    );
