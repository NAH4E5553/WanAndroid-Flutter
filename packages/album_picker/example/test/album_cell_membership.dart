import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts violations across rendered album-picker grid cells whose keys
/// follow `ValueKey('<generation>:<assetId>:<size>')`.
///
/// Returns `(foreign, staleGen, imageCells)`:
///  - `foreign`: cells at the current generation whose asset id is NOT in
///    the target album (a cross-group leftover),
///  - `staleGen`: cells carrying a generation other than the current one
///    (an old-snapshot leftover, even if its asset id is legitimate),
///  - `imageCells`: total cells inspected — callers assert this is positive
///    (against a non-empty target group) so the check cannot vacuously pass.
///
/// Panel cover thumbnails (`<gen>:cover:<albumId>`) parse as image cells, so
/// the check is only meaningful while the album panel is closed — matching
/// how the switch loop runs.
(int, int, int) albumCellViolations(
  WidgetTester tester, {
  required int currentGeneration,
  required Set<String> targetAssetIds,
}) {
  final cellKeyRe = RegExp(r'^(\d+):(.*):(\d+)$');
  var foreign = 0;
  var staleGen = 0;
  var imageCells = 0;
  for (final widget in tester.widgetList(
    find.byWidgetPredicate((w) => w.key is ValueKey<String>),
  )) {
    final match = cellKeyRe.firstMatch((widget.key! as ValueKey<String>).value);
    if (match == null) continue;
    imageCells++;
    final cellGeneration = int.parse(match.group(1)!);
    final assetId = match.group(2)!;
    if (cellGeneration != currentGeneration) {
      staleGen++;
    } else if (!targetAssetIds.contains(assetId)) {
      foreign++;
    }
  }
  return (foreign, staleGen, imageCells);
}
