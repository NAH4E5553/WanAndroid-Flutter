import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wanandroid_stage0_prototypes/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('web history is consumed before the reader route is popped', (
    tester,
  ) async {
    await tester.pumpWidget(const app.ReaderBackPrototypeApp());

    await _openReaderWithHistory(tester);
    await tester.binding.handlePopRoute();
    await _waitForDiagnostic(tester, 'webBacks=1');
    await _waitForDiagnostic(tester, 'currentHistory=false');
    await _waitForDiagnostic(tester, 'blockedPops=1');
    await _waitForDiagnostic(tester, 'backBusy=false');
    expect(find.byKey(const Key('status')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _waitForResource(tester, 'mounted=1 disposed=1 webBacks=1');
    expect(find.byKey(const Key('open-reader-route')), findsOneWidget);

    await _openReaderWithHistory(tester);
    await _tap(tester, const Key('reader-top-back'));
    await _waitForDiagnostic(tester, 'webBacks=1');
    await _waitForDiagnostic(tester, 'currentHistory=false');
    await _waitForDiagnostic(tester, 'backBusy=false');
    await _tap(tester, const Key('reader-top-back'));
    await _waitForResource(tester, 'mounted=2 disposed=2 webBacks=2');

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _openReaderWithHistory(tester);
      await tester.dragFrom(
        const Offset(1, 420),
        const Offset(360, 0),
        touchSlopY: 0,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('status')), findsOneWidget);
      expect(_diagnostics(tester), contains('currentHistory=true'));

      await _tap(tester, const Key('reader-top-back'));
      await _waitForDiagnostic(tester, 'currentHistory=false');
      await _waitForDiagnostic(tester, 'backBusy=false');
      await tester.dragFrom(
        const Offset(1, 420),
        const Offset(360, 0),
        touchSlopY: 0,
      );
      await tester.pumpAndSettle();
      await _waitForResource(tester, 'mounted=3 disposed=3 webBacks=3');
    }
  });
}

Future<void> _openReaderWithHistory(WidgetTester tester) async {
  await _tap(tester, const Key('open-reader-route'));
  await tester.pump(const Duration(milliseconds: 500));
  await _waitForStatus(tester, 'finished:');
  await _tap(tester, const Key('establish-history'));
  await _waitForDiagnostic(tester, 'historyProbeReady=true');
  expect(_diagnostics(tester), contains('currentHistory=true'));
}

String _diagnostics(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('diagnostics'))).data!;

Future<void> _tap(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _waitForStatus(WidgetTester tester, String value) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    final status = tester.widget<Text>(find.byKey(const Key('status'))).data!;
    if (status.contains(value)) return;
  }
  fail('Timed out waiting for status containing $value');
}

Future<void> _waitForDiagnostic(WidgetTester tester, String value) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (_diagnostics(tester).contains(value)) return;
  }
  fail('Timed out waiting for diagnostics containing $value');
}

Future<void> _waitForResource(WidgetTester tester, String value) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    final diagnostics = tester
        .widget<Text>(find.byKey(const Key('resource-diagnostics')))
        .data!;
    if (diagnostics.contains(value)) return;
  }
  fail('Timed out waiting for resource diagnostics containing $value');
}
