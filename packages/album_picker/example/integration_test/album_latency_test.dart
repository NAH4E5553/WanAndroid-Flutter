import 'package:album_picker/models.dart';
import 'package:album_picker/src/data/repository/implementation/channel_album_repository.dart';
import 'package:album_picker/src/features/picker/view/album_picker_screen.dart';
import 'package:album_picker/src/features/picker/view_model/album_picker_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/album_performance_metrics.dart';
import 'album_perf_test.dart' as perf;

/// Read-only existing-library diagnosis: no fixture seeding, exports, cleanup,
/// personal identifiers or image bytes in reports. First opening of this test
/// is NOT an OS-cold measurement; system caches are deliberately untouched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('first-screen stages and UI/raster timing', (tester) async {
    expect(const bool.fromEnvironment('ALBUM_LATENCY'), isTrue);
    final access = ChannelAlbumRepository();
    var permission = await access.permission();
    if (permission != AlbumPermission.full) {
      permission = await access.permission(request: true);
    }
    expect(permission, AlbumPermission.full);
    await access.close();
    perf.evidence['scope'] = 'readOnlyExistingLibrary';
    perf.evidence['cacheCondition'] = 'OS cache uncontrolled; no cache purge';
    final openings = <Map<String, Object?>>[];
    perf.evidence['openings'] = openings;
    for (var attempt = 0; attempt < 3; attempt++) {
      final clock = Stopwatch()..start();
      final events = <Map<String, Object?>>[];
      final counts = <String, int>{};
      final repo = perf.MeasuredRepo(
        ChannelAlbumRepository(),
        onTiming: (kind, ms) {
          counts[kind] = (counts[kind] ?? 0) + 1;
          // Bounded, relative timings only; never record asset/group identity.
          if (events.length < 200) {
            events.add({
              'atMs': clock.elapsedMilliseconds,
              'kind': kind,
              'durationMs': ms,
            });
          }
        },
      );
      final vm = AlbumPickerViewModel(repo);
      final row = <String, Object?>{
        'attempt': attempt + 1,
        'events': events,
        'callCounts': counts,
      };
      openings.add(row);
      final samples = <Map<String, Object?>>[];
      row['progress'] = samples;
      var maxPumpMs = 0;
      var lastSampleMs = -1000;
      var lastGeneration = -1;
      void stateChanged() {
        if (vm.state.generation != lastGeneration) {
          lastGeneration = vm.state.generation;
          if (events.length < 200) {
            events.add({
              'atMs': clock.elapsedMilliseconds,
              'kind': 'generation',
              'value': lastGeneration,
            });
          }
        }
      }

      vm.addListener(stateChanged);
      stateChanged();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: AlbumPickerScreen(model: vm, onComplete: (_) {}),
          ),
        );
        while (clock.elapsed < const Duration(seconds: 60)) {
          final pump = Stopwatch()..start();
          await tester.pump(const Duration(milliseconds: 100));
          if (pump.elapsedMilliseconds > maxPumpMs) {
            maxPumpMs = pump.elapsedMilliseconds;
          }
          final progress = albumGridProgress(tester);
          if (!vm.state.loading && vm.state.snapshot != null) {
            row.putIfAbsent('metadataMs', () => clock.elapsedMilliseconds);
            row['assets'] = vm.state.assets.length;
          }
          if (!vm.state.loading &&
              (vm.state.assets.isEmpty ||
                  (progress['visible']! > 0 && progress['pending'] == 0))) {
            row.putIfAbsent('visibleReadyMs', () => clock.elapsedMilliseconds);
          }
          // Retain the legacy predicate as a diagnostic, not readiness.
          final legacy =
              find.byIcon(Icons.image_outlined).evaluate().isEmpty &&
              find.byType(Image).evaluate().length >= 12;
          if (legacy) {
            row.putIfAbsent('legacyReadyMs', () => clock.elapsedMilliseconds);
          }
          row['maxPumpMs'] = maxPumpMs;
          if (clock.elapsedMilliseconds - lastSampleMs >= 1000 ||
              (row.containsKey('visibleReadyMs') && legacy)) {
            lastSampleMs = clock.elapsedMilliseconds;
            if (samples.length < 65) {
              samples.add({
                'atMs': clock.elapsedMilliseconds,
                'loading': vm.state.loading,
                'generation': vm.state.generation,
                ...progress,
              });
            }
            await perf.flushReport();
          }
          if (row.containsKey('visibleReadyMs') &&
              (legacy || vm.state.assets.length < 12)) {
            break;
          }
        }
        row['thumbnailMs'] = perf.describeList(repo.thumbnailMs);
        await perf.flushReport();
        expect(
          row.containsKey('visibleReadyMs'),
          isTrue,
          reason: 'visible first screen must finish within 60 seconds',
        );
        if (attempt == 2) {
          final frames = <FrameTiming>[];
          void timings(List<FrameTiming> batch) => frames.addAll(batch);
          SchedulerBinding.instance.addTimingsCallback(timings);
          try {
            await tester.pump();
            final start = SchedulerBinding
                .instance
                .currentSystemFrameTimeStamp
                .inMicroseconds;
            final scroll = Stopwatch()..start();
            var down = true;
            while (scroll.elapsed < const Duration(seconds: 60)) {
              await tester.fling(
                find.byType(GridView),
                Offset(0, down ? -1400 : 1400),
                6000,
                warnIfMissed: false,
              );
              down = !down;
              await tester.pump(const Duration(milliseconds: 280));
            }
            await tester.pump();
            final end = SchedulerBinding
                .instance
                .currentSystemFrameTimeStamp
                .inMicroseconds;
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 1200)),
            );
            perf.evidence['scrollFramesV2'] = summarizeAlbumFrames(
              frames,
              startUs: start,
              endUs: end,
              refreshRate: tester.view.display.refreshRate,
            );
            expect(
              (perf.evidence['scrollFramesV2'] as Map)['samples'],
              greaterThan(0),
            );
          } finally {
            SchedulerBinding.instance.removeTimingsCallback(timings);
          }
        }
      } finally {
        vm.removeListener(stateChanged);
        await tester.pumpWidget(const SizedBox.shrink());
        vm.dispose();
        await perf.flushReport();
      }
    }
    perf.evidence['complete'] = true;
    await perf.flushReport();
  }, timeout: const Timeout(Duration(minutes: 6)));
}
