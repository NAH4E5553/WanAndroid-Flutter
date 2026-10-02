import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Summaries are stage durations, not FPS or a count of dropped frames.
Map<String, Object?> summarizeAlbumFrames(
  List<FrameTiming> frames, {
  required int startUs,
  required int endUs,
  required double refreshRate,
}) {
  final selected = frames.where((f) {
    final timestamp = f.timestampInMicroseconds(FramePhase.vsyncStart);
    return timestamp >= startUs && timestamp < endUs;
  }).toList();
  final budgetMs = 1000 / refreshRate;
  Map<String, Object?> stage(Duration Function(FrameTiming) read) {
    final values = selected.map((f) => read(f).inMicroseconds / 1000).toList()
      ..sort();
    double? percentile(double fraction) =>
        values.isEmpty ? null : values[((values.length - 1) * fraction).ceil()];
    return {
      'samples': values.length,
      'p50Ms': percentile(.50),
      'p90Ms': percentile(.90),
      'p95Ms': percentile(.95),
      'p99Ms': percentile(.99),
      'maxMs': values.isEmpty ? null : values.last,
      'overBudgetRatio': values.isEmpty
          ? null
          : values.where((v) => v > budgetMs).length / values.length,
    };
  }

  return {
    'schema': 2,
    'refreshRateHz': refreshRate,
    'budgetMs': budgetMs,
    'samples': selected.length,
    'uiBuild': stage((f) => f.buildDuration),
    'raster': stage((f) => f.rasterDuration),
    'totalSpanDiagnosticOnly': stage((f) => f.totalSpan),
  };
}

/// Measures grid cells intersecting the viewport. Cached offscreen cells do
/// not delay first-screen readiness. Image widgets alone do not prove decode.
Map<String, int> albumGridProgress(WidgetTester tester) {
  final counts = <String, int>{
    'visible': 0,
    'decoded': 0,
    'pending': 0,
    'terminal': 0,
    'built': 0,
    'builtPending': 0,
  };
  final grid = find.byType(GridView);
  if (grid.evaluate().length != 1) return counts;
  final viewport = tester.getRect(grid);
  final cells = find.descendant(
    of: grid,
    skipOffstage: false,
    matching: find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          RegExp(r'^\d+:.*:\d+$').hasMatch((w.key! as ValueKey<String>).value),
      skipOffstage: false,
    ),
  );
  for (final element in cells.evaluate()) {
    var terminal = false;
    var decoded = false;
    void inspect(Element child) {
      final widget = child.widget;
      if (widget is Icon &&
          (widget.icon == Icons.refresh ||
              widget.icon == Icons.cloud_outlined ||
              widget.icon == Icons.broken_image)) {
        terminal = true;
      }
      if (widget is RawImage && widget.image != null) decoded = true;
      child.visitChildElements(inspect);
    }

    inspect(element);
    final pending = !terminal && !decoded;
    counts['built'] = counts['built']! + 1;
    if (pending) counts['builtPending'] = counts['builtPending']! + 1;
    final render = element.findRenderObject();
    if (render is! RenderBox ||
        !render.hasSize ||
        !viewport.overlaps(render.localToGlobal(Offset.zero) & render.size)) {
      continue;
    }
    counts['visible'] = counts['visible']! + 1;
    final field = terminal
        ? 'terminal'
        : decoded
        ? 'decoded'
        : 'pending';
    counts[field] = counts[field]! + 1;
  }
  return counts;
}

bool albumFirstScreenReady(WidgetTester tester) {
  final progress = albumGridProgress(tester);
  return progress['visible']! > 0 && progress['pending'] == 0;
}
