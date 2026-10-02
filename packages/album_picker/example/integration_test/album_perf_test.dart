import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../test/album_cell_membership.dart';
import '../test/album_performance_metrics.dart';

import 'package:album_picker/models.dart';
import 'package:album_picker/src/data/repository/contract/album_repository.dart';
import 'package:album_picker/src/data/repository/implementation/channel_album_repository.dart';
import 'package:album_picker/src/features/picker/view/album_picker_screen.dart';
import 'package:album_picker/src/features/picker/view_model/album_picker_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// MI9 large-library performance verification for the album picker.
///
/// Requires --dart-define=ALBUM_PERF=true and a pre-granted permission.
/// PERF_SCALE selects the cumulative synthetic dataset target:
///   baseline → 0 (existing personal library only)
///   s1 → 1000, s2 → 5000, s3 → 10000
/// PERF_CLEANUP=true removes every recorded synthetic resource instead.
/// Metrics are aggregated in-memory and written to the app's private files
/// directory; no personal photo content, names or paths are reported.
const fixture = MethodChannel('dev.portable.album_fixture');

final evidence = <String, Object?>{};

Future<void> phase(String value) =>
    fixture.invokeMethod('phase', {'value': value});

Future<void> flushReport() =>
    fixture.invokeMethod('report', {'text': jsonEncode(evidence)});

Future<void> until(
  WidgetTester tester,
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (ready()) return;
  }
  fail('Device phase timed out');
}

/// Timing decorator over the production gateway. Adds no behaviour; records
/// call durations so the real code path is measured end to end.
final class MeasuredRepo implements AlbumRepository {
  MeasuredRepo(this.native, {this.onTiming});
  final void Function(String, int)? onTiming;
  final ChannelAlbumRepository native;
  final permissionMs = <int>[];
  final snapshotMs = <int>[];
  final thumbnailMs = <int>[];

  @override
  Stream<void> get changes => native.changes.map((_) {
    onTiming?.call('change', 0);
  });
  @override
  Future<AlbumPermission> permission({bool request = false}) async {
    final sw = Stopwatch()..start();
    try {
      return await native.permission(request: request);
    } finally {
      permissionMs.add(sw.elapsedMilliseconds);
      onTiming?.call('permission', sw.elapsedMilliseconds);
    }
  }

  @override
  Future<AlbumSnapshot> snapshot() async {
    final sw = Stopwatch()..start();
    try {
      return await native.snapshot();
    } finally {
      snapshotMs.add(sw.elapsedMilliseconds);
      onTiming?.call('snapshot', sw.elapsedMilliseconds);
    }
  }

  @override
  Future<Uint8List?> thumbnail(AlbumAsset asset, int size) async {
    final sw = Stopwatch()..start();
    try {
      return await native.thumbnail(asset, size);
    } finally {
      thumbnailMs.add(sw.elapsedMilliseconds);
      onTiming?.call('thumbnail', sw.elapsedMilliseconds);
    }
  }

  @override
  Future<AlbumFileLease> prepare(
    AlbumAsset asset,
    AlbumBudget budget,
    AlbumCancellation cancellation, {
    required bool allowNetwork,
  }) => native.prepare(asset, budget, cancellation, allowNetwork: allowNetwork);
  @override
  Future<void> manageAccess() => native.manageAccess();
  @override
  Future<void> openSettings() => native.openSettings();
  @override
  void clearImages() => native.clearImages();
  @override
  Future<void> close() => native.close();
}

int p(List<int> values, double fraction) {
  if (values.isEmpty) return 0;
  final sorted = values.toList()..sort();
  return sorted[min(sorted.length - 1, (sorted.length * fraction).floor())];
}

Object describeList(List<int> values) => values.isEmpty
    ? const []
    : {
        'n': values.length,
        'p50': p(values, 0.50),
        'p90': p(values, 0.90),
        'p99': p(values, 0.99),
        'max': values.reduce(max),
      };

/// Switch completion waits for visible requests; first-screen measurement
/// separately requires decoded RawImages via albumFirstScreenReady.
bool thumbsSettled() => find.byIcon(Icons.image_outlined).evaluate().isEmpty;

int brokenCells() =>
    find.byIcon(Icons.refresh).evaluate().length +
    find.byIcon(Icons.cloud_outlined).evaluate().length +
    find.byIcon(Icons.broken_image).evaluate().length;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const scale = String.fromEnvironment('PERF_SCALE', defaultValue: 'baseline');
  const cleanupOnly = bool.fromEnvironment('PERF_CLEANUP');
  final target = switch (scale) {
    's1' => 1000,
    's2' => 5000,
    's3' => 10000,
    _ => 0,
  };

  setUpAll(() async {
    expect(Platform.isAndroid, isTrue);
    // The performance round must be entered through its explicit gate, never
    // by accident from a bare drive invocation.
    expect(
      const bool.fromEnvironment('ALBUM_PERF'),
      isTrue,
      reason:
          'ALBUM_PERF dart-define gate must be set for the performance round',
    );
    // Owner-verified sweep of any rows carrying our fixture name prefixes
    // that are missing from the bookkeeping of this install.
    evidence['metricsSchema'] = 2;
    evidence['firstScreenDefinition'] =
        'visible decoded RawImages or terminal placeholders';
    evidence['sweptOrphans'] = await fixture.invokeMethod<int>('sweepOrphans');
    if (cleanupOnly) {
      final remaining = await fixture.invokeMethod<int>('cleanup');
      expect(remaining, 0);
      evidence['cleanupRemaining'] = remaining;
      return;
    }
    // Reconcile leftovers from previous runs without deleting the cumulative
    // dataset: generateDataset deletes+regenerates only on count mismatch.
    final generated =
        (await fixture.invokeMethod<Object?>('generateDataset', {
              'target': target,
            }))!
            as Map<Object?, Object?>;
    evidence['datasetGenerated'] = generated['generated'];
    evidence['datasetTotal'] = generated['total'];
    evidence['datasetElapsedMs'] = generated['elapsedMs'];
    final samples =
        (await fixture.invokeMethod<Object?>('seedPerfSamples'))!
            as Map<Object?, Object?>;
    evidence['perfSamples'] = samples['inserted'];
    final stats =
        (await fixture.invokeMethod<Object?>('datasetStats'))!
            as Map<Object?, Object?>;
    evidence['datasetBytes'] = stats['bytes'];
    evidence['scale'] = scale;
  });

  tearDownAll(() async {
    if (cleanupOnly) {
      await phase('perf_cleanup_done');
    } else {
      final cacheBytes = await fixture.invokeMethod<int>('exportCacheBytes');
      evidence['exportCacheBytesFinal'] = cacheBytes;
      await flushReport();
      await phase('perf_complete');
    }
  });

  testWidgets('permission precheck timing', (tester) async {
    if (cleanupOnly) return;
    final repo = MeasuredRepo(ChannelAlbumRepository());
    for (var i = 0; i < 10; i++) {
      expect(await repo.permission(), AlbumPermission.full);
    }
    evidence['permissionCheckMs'] = describeList(repo.permissionMs);
    await repo.close();
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('metadata snapshot cold and warm timing', (tester) async {
    if (cleanupOnly) return;
    final repo = MeasuredRepo(ChannelAlbumRepository());
    final snapshot = await repo.snapshot();
    for (var i = 0; i < 3; i++) {
      await repo.snapshot();
    }
    evidence['snapshotMs'] = describeList(repo.snapshotMs);
    evidence['assetCount'] = snapshot.assets.length;
    evidence['groupCount'] = snapshot.groups.length;
    await repo.close();
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets('first open, sustained scroll, album switching', (tester) async {
    if (cleanupOnly) return;
    final repo = MeasuredRepo(ChannelAlbumRepository());
    final vm = AlbumPickerViewModel(repo);
    addTearDown(vm.dispose);

    final openSw = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        home: AlbumPickerScreen(model: vm, onComplete: (_) {}),
      ),
    );
    await until(tester, () => !vm.state.loading);
    evidence['firstOpenMetadataMs'] = openSw.elapsedMilliseconds;
    await until(
      tester,
      () => albumFirstScreenReady(tester),
      timeout: const Duration(seconds: 60),
    );
    evidence['firstOpenThumbsMs'] = openSw.elapsedMilliseconds;
    evidence['firstOpenBrokenCells'] = brokenCells();
    evidence['firstOpenGrid'] = albumGridProgress(tester);
    evidence['memoryAfterFirstOpen'] = await fixture.invokeMethod<Object?>(
      'meminfo',
    );

    // Sustained fast scroll, alternating directions, for 60 seconds.
    final frames = <FrameTiming>[];
    void onTimings(List<FrameTiming> timings) => frames.addAll(timings);
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    addTearDown(
      () => SchedulerBinding.instance.removeTimingsCallback(onTimings),
    );
    await tester.pump();
    final frameStartUs =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
    final scrollSw = Stopwatch()..start();
    var down = true;
    var lastMemory = Duration.zero;
    final memorySamples = <Object?>[];
    final gridView = find.byType(GridView);
    while (scrollSw.elapsed < const Duration(seconds: 60)) {
      await tester.fling(
        gridView,
        Offset(0, down ? -1400 : 1400),
        6000,
        warnIfMissed: false,
      );
      down = !down;
      await tester.pump(const Duration(milliseconds: 280));
      if (scrollSw.elapsed - lastMemory > const Duration(seconds: 15)) {
        lastMemory = scrollSw.elapsed;
        memorySamples.add(await fixture.invokeMethod<Object?>('meminfo'));
      }
    }
    await tester.pump();
    final frameEndUs =
        SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
    // Profile timing batches can arrive up to one second later. Keep the
    // callback installed while draining, then filter by the vsync window.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1200)),
    );
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    evidence['scrollMemorySamples'] = memorySamples;
    evidence['scrollFramesV2'] = summarizeAlbumFrames(
      frames,
      startUs: frameStartUs,
      endUs: frameEndUs,
      refreshRate: tester.view.display.refreshRate,
    );
    expect((evidence['scrollFramesV2'] as Map)['samples'], greaterThan(0));
    evidence['scrollBrokenCells'] = brokenCells();
    evidence['thumbnailMs'] = describeList(repo.thumbnailMs);
    evidence['thumbnailCount'] = repo.thumbnailMs.length;

    // Album switching x20 between two deterministic targets.
    final snapshot = vm.state.snapshot!;
    final syntheticGroups =
        vm.state.groups
            .where((g) => g.name.startsWith('AlbumPerf_'))
            .map((g) => (g, snapshot.inGroup(g.id).length))
            .toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));
    final targetB = syntheticGroups.length >= 2
        ? syntheticGroups[1].$1.id
        : vm.state.groups[1].id;
    final targetA = syntheticGroups.isNotEmpty
        ? syntheticGroups.first.$1.id
        : 'all';
    final switchMs = <int>[];
    var stale = 0;
    var staleRenderedCells = 0;
    // Album-grid cell keys follow ValueKey('<generation>:<assetId>:<size>').
    // The membership checker is the SHARED implementation from
    // ../test/album_cell_membership.dart — the same function the standalone
    // negative-control test exercises — so the device loop and its
    // counterexample can never drift apart. Cover thumbnails inside the panel
    // use 'cover:' keys and are excluded by keeping the panel closed during
    // this check.

    for (var i = 0; i < 20; i++) {
      final next = i.isEven ? targetA : targetB;
      final sw = Stopwatch()..start();
      vm.chooseGroup(next);
      await until(
        tester,
        () => vm.state.selectedId == next && !vm.state.loading,
        timeout: const Duration(seconds: 30),
      );
      await until(tester, thumbsSettled, timeout: const Duration(seconds: 60));
      switchMs.add(sw.elapsedMilliseconds);
      final shown = vm.state.assets
          .take(vm.state.limit)
          .map((a) => a.id)
          .toSet();
      // Small personal groups legitimately show fewer cells than the page
      // limit; a stale count is only meaningful against the expected maximum.
      if (shown.length != min(vm.state.limit, vm.state.assets.length)) {
        stale++;
      }
      // Real cross-group check over ALL rendered image cells (not just the
      // current generation): leftover cells from the previous group or an
      // older generation must not survive a settled switch. A non-empty
      // target group must have rendered at least one inspected cell.
      final (foreign, staleGen, imageCells) = albumCellViolations(
        tester,
        currentGeneration: vm.state.generation,
        targetAssetIds: snapshot.inGroup(next).map((a) => a.id).toSet(),
      );
      expect(
        imageCells,
        greaterThan(0),
        reason:
            'membership check must inspect at least one grid image cell; '
            'target group $next is non-empty',
      );
      staleRenderedCells += foreign + staleGen;
      expect(
        foreign + staleGen,
        0,
        reason:
            'after a settled switch every rendered grid cell must belong '
            'to the target album at the current generation (no stale or '
            'foreign cells)',
      );
    }
    evidence['switchMs'] = describeList(switchMs);
    evidence['switchStaleCounts'] = stale;
    evidence['switchStaleRenderedCells'] = staleRenderedCells;
    evidence['memoryAfterSwitches'] = await fixture.invokeMethod<Object?>(
      'meminfo',
    );

    // Panel open/close mechanics x5. The group button is located by type
    // (the label shows whichever album is selected, often a personal group
    // name), and each open/close waits inside a deadline window because a
    // scanner-storm refresh can collapse the panel between taps.
    final panelMs = <int>[];
    for (var i = 0; i < 5; i++) {
      final sw = Stopwatch()..start();
      final openDeadline = DateTime.now().add(const Duration(seconds: 30));
      while (!vm.state.expanded && DateTime.now().isBefore(openDeadline)) {
        if (!vm.state.loading && !vm.state.busy && vm.state.canBrowse) {
          await tester.tap(find.byType(FilledButton), warnIfMissed: false);
        }
        await tester.pump(const Duration(milliseconds: 150));
      }
      panelMs.add(sw.elapsedMilliseconds);
      final closeDeadline = DateTime.now().add(const Duration(seconds: 30));
      while (vm.state.expanded && DateTime.now().isBefore(closeDeadline)) {
        await tester.tap(
          find.byKey(const ValueKey('album-backdrop')),
          warnIfMissed: false,
        );
        await tester.pump(const Duration(milliseconds: 150));
      }
    }
    evidence['panelOpenMs'] = describeList(panelMs);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await repo.close();
    await Future<void>.delayed(const Duration(seconds: 5));
    evidence['memoryAfterBrowseDispose'] = await fixture.invokeMethod<Object?>(
      'meminfo',
    );
    evidence['browseSessionPassed'] = true;
    await flushReport();
    await phase('perf_browse_passed');
  }, timeout: const Timeout(Duration(minutes: 15)));

  // The negative control for the membership checker lives in
  // ../test/album_membership_check_test.dart — a host-run widget test that
  // exercises the SAME shared implementation (albumCellViolations) against
  // three fixed scenarios, so the device loop and its counterexample share
  // one implementation and the control needs no device.

  testWidgets('open/close cycles x20 and idle memory', (tester) async {
    if (cleanupOnly) return;
    final openMs = <int>[];
    final memory = <Object?>[];
    for (var i = 0; i < 20; i++) {
      final repo = MeasuredRepo(ChannelAlbumRepository());
      final vm = AlbumPickerViewModel(repo);
      final sw = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          home: AlbumPickerScreen(model: vm, onComplete: (_) {}),
        ),
      );
      await until(tester, () => !vm.state.loading);
      await until(
        tester,
        () => albumFirstScreenReady(tester),
        timeout: const Duration(seconds: 60),
      );
      openMs.add(sw.elapsedMilliseconds);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      vm.dispose();
      if ((i + 1) % 5 == 0) {
        memory.add(await fixture.invokeMethod<Object?>('meminfo'));
      }
    }
    evidence['reopenMs'] = describeList(openMs);
    evidence['cycleMemorySamples'] = memory;
    await Future<void>.delayed(const Duration(seconds: 30));
    evidence['memoryAfter30sIdle'] = await fixture.invokeMethod<Object?>(
      'meminfo',
    );
    evidence['cyclesPassed'] = true;
    await flushReport();
    await phase('perf_cycles_passed');
  }, timeout: const Timeout(Duration(minutes: 20)));

  testWidgets(
    'export preparation: normal, large, over-budget, cancel-reselect',
    (tester) async {
      if (cleanupOnly) return;
      final repo = ChannelAlbumRepository();
      final snapshot = await repo.snapshot();
      final kinds = (await fixture.invokeMethod<List<Object?>>(
        'describeIntegrity',
      ))!.cast<Map<Object?, Object?>>();
      String? idOf(String kind) {
        for (final m in kinds) {
          if (m['kind'] == kind) return m['id'] as String?;
        }
        return null;
      }

      AlbumAsset assetOf(String? id) => snapshot.assets.firstWhere(
        (a) => a.id == id,
        orElse: () => throw StateError('missing $id'),
      );

      Future<int> cacheBytes() async =>
          (await fixture.invokeMethod<int>('exportCacheBytes'))!;
      evidence['exportCacheBytesBefore'] = await cacheBytes();

      // Normal 1MP sample, three runs.
      final normalId = idOf('perfNormal');
      if (normalId != null) {
        final times = <int>[];
        for (var i = 0; i < 3; i++) {
          final sw = Stopwatch()..start();
          final lease = await repo.prepare(
            assetOf(normalId),
            AlbumBudget.avatar,
            AlbumCancellation(),
            allowNetwork: false,
          );
          times.add(sw.elapsedMilliseconds);
          await lease.release();
        }
        evidence['normalExportMs'] = describeList(times);
      }
      evidence['exportCacheBytesAfterNormal'] = await cacheBytes();

      // 12MP sample within budget.
      final largeId = idOf('perfLarge');
      if (largeId != null) {
        final sw = Stopwatch()..start();
        final lease = await repo.prepare(
          assetOf(largeId),
          AlbumBudget.avatar,
          AlbumCancellation(),
          allowNetwork: false,
        );
        evidence['largeExportMs'] = sw.elapsedMilliseconds;
        evidence['largeExportBytes'] = lease.byteLength;
        await lease.release();
      }

      // Known-over-budget request must be rejected without a full decode.
      if (largeId != null) {
        final sw = Stopwatch()..start();
        await expectLater(
          repo.prepare(
            assetOf(largeId),
            const AlbumBudget(maxPixels: 1),
            AlbumCancellation(),
            allowNetwork: false,
          ),
          throwsA(
            isA<AlbumFailure>().having((e) => e.code, 'code', 'budgetExceeded'),
          ),
        );
        evidence['overBudgetRejectMs'] = sw.elapsedMilliseconds;
      }

      // Cancel mid-preparation, then reselect immediately: the scheduler may
      // either succeed once the worker stops or fail exportUnavailable; it must
      // never hang or double-prepare.
      final largeBId = idOf('perfLargeB');
      if (largeBId != null) {
        final sw = Stopwatch()..start();
        final cancellation = AlbumCancellation();
        final first = repo.prepare(
          assetOf(largeBId),
          AlbumBudget.avatar,
          cancellation,
          allowNetwork: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        cancellation.cancel();
        var firstOutcome = 'unknown';
        try {
          final lease = await first.timeout(const Duration(seconds: 10));
          await lease.release();
          firstOutcome = 'lateSuccessReleased';
        } on AlbumFailure catch (e) {
          firstOutcome = e.code;
        } on TimeoutException {
          firstOutcome = 'timeout10s';
        }
        final second = repo.prepare(
          assetOf(largeBId),
          AlbumBudget.avatar,
          AlbumCancellation(),
          allowNetwork: false,
        );
        var secondOutcome = 'unknown';
        try {
          final lease = await second.timeout(const Duration(seconds: 30));
          secondOutcome = 'selected';
          await lease.release();
        } on AlbumFailure catch (e) {
          secondOutcome = e.code;
        } on TimeoutException {
          secondOutcome = 'timeout30s';
        }
        evidence['cancelReselect'] = {
          'cancelAtMs': 300,
          'firstOutcome': firstOutcome,
          'totalMs': sw.elapsedMilliseconds,
          'secondOutcome': secondOutcome,
        };
      }
      evidence['exportCacheBytesAfterExports'] = await cacheBytes();
      await repo.close();
      await Future<void>.delayed(const Duration(seconds: 3));
      evidence['exportCacheBytesAfterClose'] = await fixture.invokeMethod<int>(
        'exportCacheBytes',
      );
      evidence['exportPassed'] = true;
      await flushReport();
      await phase('perf_export_passed');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
