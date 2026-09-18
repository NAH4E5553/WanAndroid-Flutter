import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wanandroid_stage0_prototypes/navigation/navigation_probe.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('active branch route entries restore with stable identity', (
    tester,
  ) async {
    await tester.pumpWidget(const NavigationPrototypeApp());
    await tester.pumpAndSettle();

    expect(find.text('branch:0'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('push-detail')));
    await tester.pumpAndSettle();
    final firstId = tester
        .widget<Text>(find.byKey(const ValueKey('route-instance-id')))
        .data!;

    await tester.tap(find.byKey(const ValueKey('push-same-detail')));
    await tester.pumpAndSettle();
    final secondId = tester
        .widget<Text>(find.byKey(const ValueKey('route-instance-id')))
        .data!;
    expect(secondId, isNot(firstId));

    await tester.tap(find.byKey(const ValueKey('pop-detail')));
    await tester.pumpAndSettle();
    expect(find.text(firstId), findsOneWidget);

    await tester.restartAndRestore();
    await tester.pumpAndSettle();
    expect(find.text('branch:0'), findsOneWidget);
    expect(find.text(firstId), findsOneWidget);
    expect(find.text('article:42'), findsOneWidget);
  });

  testWidgets('selected shell branch restores when the router is rebuilt', (
    tester,
  ) async {
    await tester.pumpWidget(const NavigationPrototypeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Topics'));
    await tester.pumpAndSettle();
    expect(find.text('branch:1'), findsOneWidget);

    await tester.restartAndRestore();
    await tester.pumpAndSettle();
    expect(find.text('branch:1'), findsOneWidget);
    expect(find.byKey(const ValueKey('topics-screen')), findsOneWidget);
  });

  testWidgets('router rebuild drops an inactive imperative branch stack', (
    tester,
  ) async {
    await tester.pumpWidget(const NavigationPrototypeApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('push-detail')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('route-instance-id')), findsOneWidget);
    await tester.tap(find.text('Topics'));
    await tester.pumpAndSettle();

    await tester.restartAndRestore();
    await tester.pumpAndSettle();
    expect(find.text('branch:1'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('push-detail')), findsOneWidget);
    expect(find.byKey(const ValueKey('route-instance-id')), findsNothing);
  });
}
