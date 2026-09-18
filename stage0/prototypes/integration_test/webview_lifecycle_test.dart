import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wanandroid_stage0_prototypes/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real WebView guard completes replacement; lifecycle is injected', (
    tester,
  ) async {
    app.main();
    await tester.pump();
    await _waitForText(tester, 'finished:');
    await _waitForText(tester, 'history=false');

    final initial = tester.widget<Text>(find.byKey(const Key('status'))).data!;
    expect(initial, contains('browser=1'));

    expect(
      tester.widget<Text>(find.byKey(const Key('diagnostics'))).data,
      contains('historyProbeWrites=1'),
    );
    debugPrint(
      'PLATFORM FIRST: ${tester.widget<Text>(find.byKey(const Key('callback-trace'))).data}',
    );

    await _tap(tester, const Key('establish-history'));
    await _waitForDiagnostic(tester, 'historyProbeReady=true');
    final history = _diagnostics(tester);
    expect(history, contains('currentHistory=true'));
    expect(history, contains('currentUrlScheme=file'));
    debugPrint('PLATFORM HISTORY: $history');

    await _tap(tester, const Key('reload-same'));
    await _waitForDiagnostic(tester, 'reloadHistory=true→true');
    final reload = _diagnostics(tester);
    expect(_offsetY(reload, 'reloadScroll', beforeArrow: true), greaterThan(0));
    debugPrint('PLATFORM RELOAD: $reload');

    await _tap(tester, const Key('establish-history'));
    await _waitForDiagnostic(tester, 'historyProbeReady=true');

    await _tap(tester, const Key('replace-controller'));
    await tester.pump();
    await _waitForText(tester, 'browser=2');
    await _waitForText(tester, 'finished:');

    await _waitForText(tester, 'history=false');
    expect(
      tester.widget<Text>(find.byKey(const Key('diagnostics'))).data,
      contains('historyProbeWrites=2'),
    );
    debugPrint(
      'PLATFORM REPLACEMENT: ${tester.widget<Text>(find.byKey(const Key('callback-trace'))).data}',
    );
    final replacement = _diagnostics(tester);
    expect(replacement, contains('historyBefore=true'));
    expect(replacement, contains('currentHistory=false'));
    expect(_offsetY(replacement, 'scrollBefore'), greaterThan(0));
    debugPrint('PLATFORM REPLACEMENT STATE: $replacement');

    await _tap(tester, const Key('race-replace'));
    await _waitForText(tester, 'browser=3');
    await _waitForText(tester, 'finished:');
    await _waitForText(tester, 'history=false');
    await tester.pump(const Duration(milliseconds: 500));
    final race = _diagnostics(tester);
    expect(_integer(race, 'raceIgnored'), greaterThan(0));
    debugPrint('PLATFORM RACE: $race');
    debugPrint(
      'PLATFORM RACE TRACE: ${tester.widget<Text>(find.byKey(const Key('callback-trace-all'), skipOffstage: false)).data}',
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // Live binding cannot render a frame while paused. Record both injected
    // observer events, then render after resume; this is NOT OS backgrounding.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('diagnostics'))).data,
      contains('lifecycle=resumed'),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('diagnostics'))).data,
      contains('lifecycleEvents=paused,resumed'),
    );
  });
}

String _diagnostics(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('diagnostics'))).data!;

double _offsetY(String diagnostics, String field, {bool beforeArrow = false}) {
  final suffix = beforeArrow ? r'→' : '';
  final match = RegExp('$field=Offset\\([^,]+, ([^)]+)\\)$suffix')
      .firstMatch(diagnostics);
  if (match == null) fail('Missing $field offset in: $diagnostics');
  return double.parse(match.group(1)!);
}

int _integer(String diagnostics, String field) {
  final match = RegExp('$field=(\\d+)').firstMatch(diagnostics);
  if (match == null) fail('Missing $field integer in: $diagnostics');
  return int.parse(match.group(1)!);
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _waitForDiagnostic(WidgetTester tester, String value) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (_diagnostics(tester).contains(value)) return;
  }
  fail('Timed out waiting for diagnostics containing $value');
}

Future<void> _waitForText(WidgetTester tester, String value) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    final status = tester.widget<Text>(find.byKey(const Key('status'))).data!;
    if (status.contains(value)) return;
  }
  fail('Timed out waiting for status containing $value');
}
