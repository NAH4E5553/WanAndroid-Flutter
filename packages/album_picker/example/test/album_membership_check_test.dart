import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'album_cell_membership.dart';

/// Host-run widget test (no device) proving the SHARED album-grid membership
/// checker — the same albumCellViolations implementation the on-device
/// switch loop uses — behaves correctly against three fixed scenarios.
void main() {
  const generation = 7;
  const targetAlbumId = 'external_primary:123';
  const targetAssetIds = {
    'content://media/external_primary/images/media/1',
    'content://media/external_primary/images/media/2',
  };

  Future<(int, int, int)> pump(WidgetTester tester, List<String> keys) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              for (final key in keys)
                KeyedSubtree(
                  key: ValueKey<String>(key),
                  child: const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    return albumCellViolations(
      tester,
      currentGeneration: generation,
      targetAssetIds: targetAssetIds,
    );
  }

  testWidgets('scenario 1: a normal cell passes with no violations', (
    tester,
  ) async {
    final (foreign, staleGen, imageCells) = await pump(tester, [
      '$generation:content://media/external_primary/images/media/1:256',
    ]);
    expect(
      foreign,
      0,
      reason: 'target-album cell at current generation is clean',
    );
    expect(staleGen, 0);
    expect(imageCells, 1);
  });

  testWidgets('scenario 2: current-generation foreign identity fails', (
    tester,
  ) async {
    final (foreign, staleGen, imageCells) = await pump(tester, [
      '$generation:content://media/external_primary/images/media/999:256',
    ]);
    expect(foreign, 1, reason: 'an id outside the target album is foreign');
    expect(staleGen, 0);
    expect(imageCells, 1);
  });

  testWidgets('scenario 3: old-generation legitimate identity fails', (
    tester,
  ) async {
    final (foreign, staleGen, imageCells) = await pump(tester, [
      '${generation - 1}:content://media/external_primary/images/media/1:256',
    ]);
    expect(foreign, 0);
    expect(
      staleGen,
      1,
      reason: 'an old-generation cell is stale even when its album matches',
    );
    expect(imageCells, 1);
  });

  testWidgets('panel cover keys are recognized as image cells', (tester) async {
    // Documents the cover-key caveat: '<gen>:cover:<albumId>' parses like an
    // image cell, which is why the device check only runs panel-closed.
    final (foreign, staleGen, imageCells) = await pump(tester, [
      '$generation:cover:$targetAlbumId',
    ]);
    expect(imageCells, 1);
    expect(foreign + staleGen, 1);
  });
}
