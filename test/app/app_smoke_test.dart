import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/app/app.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/fake_home_repository.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_view_model.dart';

void main() {
  testWidgets('renders the fake home vertical slice', (
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

    expect(find.text('每日一问'), findsOneWidget);
    expect(find.text('最新博文'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('专题'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}
