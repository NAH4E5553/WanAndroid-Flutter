import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/diagnostics/startup_metrics.dart';

void main() {
  test('disabled diagnostics emit nothing and points are recorded once', () {
    int clock = 100;
    final List<Map<String, Object>> events = <Map<String, Object>>[];
    final StartupMetrics disabled = StartupMetrics(
      enabled: false,
      clock: () => clock,
      emit: events.add,
    )..start();
    disabled.mark('dependencies_ready');
    expect(events, isEmpty);
    final StartupMetrics metrics = StartupMetrics(
      enabled: true,
      clock: () => clock,
      emit: events.add,
    )..start();
    clock = 150;
    metrics.mark('dependencies_ready');
    clock = 900;
    metrics.mark('dependencies_ready');
    expect(events.map((e) => e['point']), <String>[
      'dart_main',
      'dependencies_ready',
    ]);
    expect(events.last['dart_us'], 50);
  });

  testWidgets('matches built frame and uses raster finish, not batch arrival', (
    WidgetTester tester,
  ) async {
    int clock = 100;
    final List<Map<String, Object>> events = <Map<String, Object>>[];
    final StartupMetrics metrics = StartupMetrics(
      enabled: true,
      clock: () => clock,
      emit: events.add,
    )..start();
    clock = 220;
    metrics.frame('home_content_raster', stillValid: () => true);
    metrics.frame('hidden', stillValid: () => false);
    tester.binding.scheduleFrame();
    await tester.pump();
    clock = 1000;
    metrics.recordTimings(<FrameTiming>[
      _timing(110, 200, 210), // Earlier frame cannot complete content.
    ]);
    expect(events.where((e) => e['point'] == 'home_content_raster'), isEmpty);
    metrics.recordTimings(<FrameTiming>[_timing(215, 240, 300)]);
    expect(events.last['point'], 'home_content_raster');
    expect(events.last['dart_us'], 200);
    expect(events.where((e) => e['point'] == 'hidden'), isEmpty);
    clock = 1100;
    metrics.frame('home_content_raster', stillValid: () => true);
    tester.binding.scheduleFrame();
    await tester.pump();
    clock = 2000;
    metrics.recordTimings(<FrameTiming>[_timing(1090, 1120, 1300)]);
    expect(
      events.where((e) => e['point'] == 'home_content_raster'),
      hasLength(1),
    );
  });

  testWidgets(
    'stale snapshot at submission and unmatched frames are rejected',
    (WidgetTester tester) async {
      int clock = 100;
      bool valid = true;
      final List<Map<String, Object>> events = <Map<String, Object>>[];
      final StartupMetrics metrics = StartupMetrics(
        enabled: true,
        clock: () => clock,
        emit: events.add,
      )..start();
      clock = 220;
      metrics.frame('stale', stillValid: () => valid);
      metrics.frame('unmatched', stillValid: () => true);
      valid = false;
      tester.binding.scheduleFrame();
      await tester.pump();
      clock = 1000;
      metrics.recordTimings(<FrameTiming>[_timing(230, 240, 300)]);
      expect(events.map((e) => e['point']), <String>[
        'dart_main',
        'first_raster',
      ]);
    },
  );
}

FrameTiming _timing(int begin, int end, int raster) => FrameTiming(
  vsyncStart: begin - 1,
  buildStart: begin,
  buildFinish: end,
  rasterStart: end + 1,
  rasterFinish: raster,
  rasterFinishWallTime: raster,
);
