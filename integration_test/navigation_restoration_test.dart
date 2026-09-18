import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wanandroid_flutter/src/app/app.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/fake_home_repository.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_view_model.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('restores the inactive home detail stack and active branch', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeRepositoryProvider.overrideWithValue(const FakeHomeRepository()),
        ],
        child: const WanAndroidApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('用固定 Fake 数据建立第一个 Flutter 垂直切片'));
    await tester.pumpAndSettle();
    expect(find.text('文章预览 #101'), findsOneWidget);

    await tester.tap(find.text('专题'));
    await tester.pumpAndSettle();
    expect(find.text('专题完整交互将在阶段 3 实现。'), findsOneWidget);

    await tester.restartAndRestore();
    await tester.pumpAndSettle();
    expect(
      find.text('专题完整交互将在阶段 3 实现。'),
      findsOneWidget,
      reason: 'Visible texts after restore: ${_visibleTexts(tester)}',
    );

    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(find.text('文章预览 #101'), findsOneWidget);
  });
}

List<String> _visibleTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text widget) => widget.data)
    .whereType<String>()
    .toList(growable: false);
