import 'dart:io';
import 'dart:typed_data';

import 'package:album_picker/models.dart';
import 'package:album_picker/src/data/repository/implementation/channel_album_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'controlled PhotoKit snapshot, local thumbnail, PNG export, limits and isolated release',
    (tester) async {
      // Never enumerate a developer's or user's ordinary library.
      expect(
        const bool.fromEnvironment('ALBUM_CONTROLLED_LIBRARY'),
        isTrue,
        reason: 'Run only on the fresh dedicated simulator seeded by the native probe.',
      );
      expect(Platform.isIOS, isTrue);
      final repository = ChannelAlbumRepository();
      try {
        expect(await repository.permission(), AlbumPermission.full);
        final snapshot = await repository.snapshot();
        // Fresh simulators include Apple samples; export only our synthetic fixtures.
        final controlled = snapshot.assets
            .where(
              (a) =>
                  (a.width == 8 && a.height == 4) ||
                  (a.width == 4 && a.height == 8),
            )
            .toList();
        expect(controlled.length, 2);
        final asset = controlled.first;
        expect(await repository.thumbnail(asset, 64), isNotNull);
        final output = await repository.prepare(
          asset,
          AlbumBudget.avatar,
          AlbumCancellation(),
          allowNetwork: false,
        );
        final file = File(output.path);
        expect(await file.exists(), isTrue);
        final bytes = await file.readAsBytes();
        expect(bytes.length, output.byteLength);
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final data = ByteData.sublistView(bytes);
        expect(data.getUint32(16), output.width);
        expect(data.getUint32(20), output.height);
        int offset = 8;
        while (offset + 12 <= bytes.length) {
          final size = data.getUint32(offset);
          final type = String.fromCharCodes(
            bytes.sublist(offset + 4, offset + 8),
          );
          expect(['eXIf', 'tEXt', 'iTXt', 'zTXt'].contains(type), isFalse);
          offset += size + 12;
        }
        await output.release();
        await output.release();
        expect(await file.exists(), isFalse);
        expect(
          (await repository.snapshot()).assets.length,
          snapshot.assets.length,
          reason: 'release must not delete source photos',
        );
        await expectLater(
          repository.prepare(
            asset,
            const AlbumBudget(outputBytes: 1),
            AlbumCancellation(),
            allowNetwork: false,
          ),
          throwsA(
            isA<AlbumFailure>().having((e) => e.code, 'code', 'budgetExceeded'),
          ),
        );
        final retry = await repository.prepare(
          asset,
          AlbumBudget.avatar,
          AlbumCancellation(),
          allowNetwork: false,
        );
        await retry.release();
        repository.clearImages();
        expect(await repository.thumbnail(asset, 64), isNotNull);
      } finally {
        await repository.close();
      }
    },
  );
}
