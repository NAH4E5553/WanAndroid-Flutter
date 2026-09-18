import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wanandroid_stage0_prototypes/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const externalInputEnabled = bool.fromEnvironment(
    'STAGE0_EXTERNAL_SYSTEM_INPUT',
  );

  testWidgets(
    'records OS-dispatched back and foreground lifecycle transitions',
    (tester) async {
      await tester.pumpWidget(const app.ReaderBackPrototypeApp());
      await _openReader(tester, establishHistory: true);

      debugPrint('STAGE0_EXTERNAL_BACK_HISTORY_READY');
      await _waitForDiagnostic(tester, (value) {
        return value.contains('webBacks=1') &&
            value.contains('currentHistory=false') &&
            value.contains('blockedPops=1') &&
            value.contains('backBusy=false');
      });

      debugPrint('STAGE0_EXTERNAL_BACK_ROUTE_READY');
      await _waitForResource(tester, 'mounted=1 disposed=1 webBacks=1');

      await _openReader(tester, establishHistory: false);
      debugPrint('STAGE0_EXTERNAL_LIFECYCLE_READY');
      await _waitForDiagnostic(tester, (value) {
        return value.contains('lifecycle=resumed') && value.contains('paused');
      });
      final lifecycle = _diagnostics(tester);
      debugPrint('STAGE0_EXTERNAL_LIFECYCLE_RESULT $lifecycle');

      await _tap(tester, const Key('reader-top-back'));
      await _waitForResource(tester, 'mounted=2 disposed=2 webBacks=1');
    },
    skip:
        !externalInputEnabled ||
        defaultTargetPlatform != TargetPlatform.android,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _openReader(
  WidgetTester tester, {
  required bool establishHistory,
}) async {
  await _tap(tester, const Key('open-reader-route'));
  await tester.pump(const Duration(milliseconds: 500));
  await _waitForStatus(tester, 'finished:');
  if (!establishHistory) return;
  await _tap(tester, const Key('establish-history'));
  await _waitForDiagnostic(
    tester,
    (value) => value.contains('historyProbeReady=true'),
  );
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
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    final status = tester.widget<Text>(find.byKey(const Key('status'))).data!;
    if (status.contains(value)) return;
  }
  fail('Timed out waiting for status containing $value');
}

Future<void> _waitForDiagnostic(
  WidgetTester tester,
  bool Function(String value) predicate,
) async {
  for (var attempt = 0; attempt < 600; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (predicate(_diagnostics(tester))) return;
  }
  fail('Timed out waiting for diagnostics: ${_diagnostics(tester)}');
}

Future<void> _waitForResource(WidgetTester tester, String value) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    final diagnostics = tester
        .widget<Text>(
          find.byKey(const Key('resource-diagnostics'), skipOffstage: false),
        )
        .data!;
    if (diagnostics.contains(value)) return;
  }
  fail('Timed out waiting for resource diagnostics containing $value');
}
