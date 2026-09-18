import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_stage0_prototypes/reader/reader_failure_classifier.dart';
import 'package:wanandroid_stage0_prototypes/reader/reader_load_guard.dart';
import 'package:wanandroid_stage0_prototypes/reader/reader_probe_callbacks.dart';

void main() {
  final url = Uri.parse('about:blank');
  const timeout = Duration(seconds: 1);

  testWidgets(
    'timeout retry rejects old completion error and progress without cancelling retry timer',
    (tester) async {
      final probe = ReaderProbeCallbacks(
        onChanged: () {},
        timeoutDuration: timeout,
      );
      addTearDown(probe.dispose);
      final old = probe.begin(url);
      await tester.pump(timeout);
      expect(probe.snapshot.phase, ReaderLoadPhase.timedOut);
      final retry = probe.begin(url);
      var historyReads = 0;
      await probe.pageFinished(old, '$url', () async {
        historyReads++;
        return true;
      }, source: 'injected');
      probe.pageFailed(old, '$url', isMainFrame: true, source: 'injected');
      probe.onProgress(old, 100, source: 'injected');
      expect(probe.snapshot.browserInstanceId, retry);
      expect(probe.snapshot.phase, ReaderLoadPhase.loading);
      expect(probe.progress, 0);
      expect(historyReads, 0);
      expect(probe.historyProbeWrites, 0);
      expect(probe.collectionTargetProbe, isNull);
      expect(probe.snapshot.ignoredCallbacks, 3);
      await tester.pump(timeout);
      expect(probe.snapshot.phase, ReaderLoadPhase.timedOut);
      expect(
        probe.trace.where((line) => line.startsWith('injected')),
        hasLength(3),
      );
    },
  );

  testWidgets(
    'retry success alone publishes effect probes and cancels its deadline',
    (tester) async {
      final probe = ReaderProbeCallbacks(
        onChanged: () {},
        timeoutDuration: timeout,
      );
      addTearDown(probe.dispose);
      final old = probe.begin(url);
      await tester.pump(timeout);
      final retry = probe.begin(url);
      await probe.pageFinished(
        retry,
        '$url',
        () async => false,
        source: 'injected',
      );
      probe.pageFailed(old, '$url', isMainFrame: true, source: 'injected');
      probe.onProgress(old, 23, source: 'injected');
      await tester.pump(timeout);
      expect(probe.snapshot.phase, ReaderLoadPhase.loaded);
      expect(probe.historyProbeWrites, 1);
      expect(probe.collectionTargetProbe, url);
      expect(probe.status, contains('history=false'));
    },
  );

  testWidgets(
    'old asynchronous history result cannot publish after replacement',
    (tester) async {
      final probe = ReaderProbeCallbacks(
        onChanged: () {},
        timeoutDuration: timeout,
      );
      addTearDown(probe.dispose);
      final old = probe.begin(url);
      final history = Completer<bool>();
      final finish = probe.pageFinished(
        old,
        '$url',
        () => history.future,
        source: 'injected',
      );
      final retry = probe.begin(url);
      history.complete(true);
      await finish;
      expect(probe.snapshot.browserInstanceId, retry);
      expect(probe.snapshot.phase, ReaderLoadPhase.loading);
      expect(probe.historyProbeWrites, 0);
      expect(probe.collectionTargetProbe, isNull);
      await tester.pump(timeout);
      expect(probe.snapshot.phase, ReaderLoadPhase.timedOut);
    },
  );

  testWidgets('old callbacks cannot clear current failure or restore target', (
    tester,
  ) async {
    final probe = ReaderProbeCallbacks(
      onChanged: () {},
      timeoutDuration: timeout,
    );
    addTearDown(probe.dispose);
    final old = probe.begin(url);
    await tester.pump(timeout);
    final retry = probe.begin(url);
    probe.pageFailed(retry, '$url', isMainFrame: true, source: 'injected');
    await probe.pageFinished(old, '$url', () async => true, source: 'injected');
    probe.onProgress(old, 100, source: 'injected');
    expect(probe.snapshot.phase, ReaderLoadPhase.failed);
    expect(probe.historyProbeWrites, 0);
    expect(probe.collectionTargetProbe, isNull);
    await tester.pump(timeout);
    expect(probe.snapshot.phase, ReaderLoadPhase.failed);
  });

  testWidgets('unknown URL and unproven main-frame error remain unaccepted', (
    tester,
  ) async {
    final probe = ReaderProbeCallbacks(
      onChanged: () {},
      timeoutDuration: timeout,
    );
    addTearDown(probe.dispose);
    final id = probe.begin(url);
    await probe.pageFinished(
      id,
      'https://fixture.invalid/other',
      () async => true,
      source: 'injected',
    );
    for (final mainFrame in [false, null]) {
      probe.pageFailed(id, '$url', isMainFrame: mainFrame, source: 'injected');
    }
    probe.pageFailed(id, null, isMainFrame: true, source: 'injected');
    expect(probe.snapshot.phase, ReaderLoadPhase.loading);
    expect(probe.historyProbeWrites, 0);
    await tester.pump(timeout);
    expect(probe.snapshot.phase, ReaderLoadPhase.timedOut);
  });

  testWidgets('subresource error stays diagnostic after readable main page', (
    tester,
  ) async {
    final probe = ReaderProbeCallbacks(
      onChanged: () {},
      timeoutDuration: timeout,
    );
    addTearDown(probe.dispose);
    final id = probe.begin(url);
    probe.pageFailed(
      id,
      'https://fixture.invalid/image.png',
      isMainFrame: false,
      source: 'injected',
    );
    expect(probe.snapshot.phase, ReaderLoadPhase.loading);
    expect(probe.diagnosticFailures, 1);
    await probe.pageFinished(id, '$url', () async => false, source: 'injected');
    expect(probe.snapshot.phase, ReaderLoadPhase.loaded);
    expect(probe.historyProbeWrites, 1);
  });

  testWidgets('TLS and renderer failures publish explicit full-page kinds', (
    tester,
  ) async {
    final tlsProbe = ReaderProbeCallbacks(
      onChanged: () {},
      timeoutDuration: timeout,
    );
    addTearDown(tlsProbe.dispose);
    final tlsId = tlsProbe.begin(url);
    tlsProbe.pageFailed(
      tlsId,
      '$url',
      isMainFrame: true,
      source: 'injected',
      kind: ReaderFailureKind.tls,
    );
    expect(tlsProbe.snapshot.phase, ReaderLoadPhase.failed);
    expect(tlsProbe.pageFailureKind, ReaderFailureKind.tls);

    final rendererProbe = ReaderProbeCallbacks(
      onChanged: () {},
      timeoutDuration: timeout,
    );
    addTearDown(rendererProbe.dispose);
    final rendererId = rendererProbe.begin(url);
    rendererProbe.pageFailed(
      rendererId,
      null,
      isMainFrame: null,
      source: 'injected',
      kind: ReaderFailureKind.renderer,
    );
    expect(rendererProbe.snapshot.phase, ReaderLoadPhase.failed);
    expect(rendererProbe.pageFailureKind, ReaderFailureKind.renderer);
  });

  testWidgets('HTTP without provable main URL remains diagnostic', (
    tester,
  ) async {
    final probe = ReaderProbeCallbacks(
      onChanged: () {},
      timeoutDuration: timeout,
    );
    addTearDown(probe.dispose);
    final id = probe.begin(url);
    probe.httpFailed(id, requestUrl: null, statusCode: 500, source: 'injected');
    probe.httpFailed(
      id,
      requestUrl: Uri.parse('https://fixture.invalid/image.png'),
      statusCode: 404,
      source: 'injected',
    );
    expect(probe.snapshot.phase, ReaderLoadPhase.loading);
    expect(probe.diagnosticFailures, 2);
    probe.httpFailed(id, requestUrl: url, statusCode: 503, source: 'injected');
    expect(probe.snapshot.phase, ReaderLoadPhase.failed);
    expect(probe.pageFailureKind, ReaderFailureKind.http);
  });

  testWidgets(
    'dispose cancels timer and rejects pending history and later callbacks',
    (tester) async {
      var changes = 0;
      final probe = ReaderProbeCallbacks(
        onChanged: () => changes++,
        timeoutDuration: timeout,
      );
      final id = probe.begin(url);
      final history = Completer<bool>();
      final finish = probe.pageFinished(
        id,
        '$url',
        () => history.future,
        source: 'injected',
      );
      probe.dispose();
      final before = changes;
      history.complete(true);
      await finish;
      probe.onProgress(id, 100, source: 'injected');
      probe.pageFailed(id, '$url', isMainFrame: true, source: 'injected');
      await tester.pump(timeout);
      expect(changes, before);
      expect(probe.historyProbeWrites, 0);
      expect(probe.collectionTargetProbe, isNull);
    },
  );

  testWidgets(
    'replacement cancels the previous deadline and trace is bounded',
    (tester) async {
      final probe = ReaderProbeCallbacks(
        onChanged: () {},
        timeoutDuration: timeout,
      );
      addTearDown(probe.dispose);
      probe.begin(url);
      await tester.pump(const Duration(milliseconds: 500));
      final retry = probe.begin(url);
      for (var i = 0; i < 40; i++) {
        probe.onProgress(retry, i, source: 'injected');
      }
      expect(probe.trace, hasLength(32));
      await tester.pump(const Duration(milliseconds: 500));
      expect(probe.snapshot.phase, ReaderLoadPhase.loading);
      await tester.pump(const Duration(milliseconds: 500));
      expect(probe.snapshot.phase, ReaderLoadPhase.timedOut);
    },
  );
}
