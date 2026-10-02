import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';

import 'album_performance_metrics.dart';

void main() {
  test('UI and raster remain fast even when total latency exceeds budget', () {
    final frames = [
      ui.FrameTiming(
        vsyncStart: 1000,
        buildStart: 21000,
        buildFinish: 25000,
        rasterStart: 31000,
        rasterFinish: 36000,
        rasterFinishWallTime: 0,
      ),
    ];
    final result = summarizeAlbumFrames(
      frames,
      startUs: 1000,
      endUs: 40000,
      refreshRate: 60,
    );
    expect((result['uiBuild'] as Map)['maxMs'], 4);
    expect((result['raster'] as Map)['maxMs'], 5);
    expect((result['uiBuild'] as Map)['overBudgetRatio'], 0);
    expect((result['raster'] as Map)['overBudgetRatio'], 0);
    expect((result['totalSpanDiagnosticOnly'] as Map)['overBudgetRatio'], 1);
  });
  test('window filters late batches and uses refresh-rate budget', () {
    ui.FrameTiming frame(int start) => ui.FrameTiming(
      vsyncStart: start,
      buildStart: start,
      buildFinish: start + 9000,
      rasterStart: start + 10000,
      rasterFinish: start + 12000,
      rasterFinishWallTime: 0,
    );
    final result = summarizeAlbumFrames(
      [frame(0), frame(1000), frame(2000)],
      startUs: 1000,
      endUs: 2000,
      refreshRate: 120,
    );
    expect(result['samples'], 1);
    expect((result['uiBuild'] as Map)['overBudgetRatio'], 1);
    expect((result['raster'] as Map)['overBudgetRatio'], 0);
    final empty = summarizeAlbumFrames(
      [],
      startUs: 0,
      endUs: 1,
      refreshRate: 60,
    );
    expect((empty['uiBuild'] as Map)['overBudgetRatio'], isNull);
  });

  testWidgets('offscreen preloading does not delay decoded first screen', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(1, 1);
    addTearDown(image.dispose);
    addTearDown(picture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 100,
            child: GridView.builder(
              scrollCacheExtent: ScrollCacheExtent.pixels(300),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
              ),
              itemCount: 20,
              itemBuilder: (_, i) => KeyedSubtree(
                key: ValueKey('1:synthetic$i:128'),
                child: i < 4
                    ? RawImage(image: image)
                    : const Icon(Icons.image_outlined),
              ),
            ),
          ),
        ),
      ),
    );
    final progress = albumGridProgress(tester);
    expect(progress['visible'], 4);
    expect(progress['decoded'], 4);
    expect(progress['builtPending'], greaterThan(0));
    expect(
      find.byIcon(Icons.image_outlined, skipOffstage: false),
      findsWidgets,
    ); // Diagnostic includes preload cells.
    expect(albumFirstScreenReady(tester), isTrue);
  });
  testWidgets('undecoded RawImage is pending; small terminal group completes', (
    tester,
  ) async {
    Future<void> show(Widget child) => tester.pumpWidget(
      MaterialApp(
        home: GridView.count(
          crossAxisCount: 4,
          children: [
            KeyedSubtree(key: const ValueKey('1:synthetic:128'), child: child),
          ],
        ),
      ),
    );
    await show(const RawImage());
    expect(albumFirstScreenReady(tester), isFalse);
    expect(albumGridProgress(tester)['pending'], 1);
    await show(const Icon(Icons.broken_image));
    expect(albumFirstScreenReady(tester), isTrue);
    expect(albumGridProgress(tester)['terminal'], 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(albumFirstScreenReady(tester), isFalse);
  });
}
