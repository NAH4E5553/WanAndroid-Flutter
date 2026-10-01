import 'dart:async';

import 'package:album_picker/models.dart';
import 'package:album_picker/src/data/repository/implementation/channel_album_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('controlled.album');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('global stable ordering across page boundary; same names retain volume identity', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'snapshot') return null;
      return {
        'assets': List.generate(
          161,
          (i) => {
            'id': 'image-${(160 - i).toString().padLeft(3, '0')}',
            'revision': 'v1',
            'time': 10,
            'width': 2,
            'height': 2,
            'albums': [i.isEven ? 'primary:1' : 'sd:1'],
          },
        ),
        'groups': [
          {'id': 'primary:1', 'name': 'Camera', 'detail': 'primary'},
          {'id': 'sd:1', 'name': 'Camera', 'detail': 'sd'},
        ],
      };
    });
    final repo = ChannelAlbumRepository(channel: channel);
    final snapshot = await repo.snapshot();
    expect(snapshot.groups.length, 3);
    expect(snapshot.inGroup('primary:1').length, 81);
    expect(snapshot.inGroup('sd:1').length, 80);
    expect(snapshot.assets.skip(79).take(3).map((a) => a.id), [
      'image-079',
      'image-080',
      'image-081',
    ]);
    await repo.close();
  });
  testWidgets(
    'thumbnail work bounded at four and stale generation never returned',
    (tester) async {
      final requests = <Completer<Uint8List>>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'thumbnail') return null;
        final request = Completer<Uint8List>();
        requests.add(request);
        return request.future;
      });
      final repo = ChannelAlbumRepository(channel: channel);
      final asset = AlbumAsset(
        id: 'fixture',
        revision: 'v1',
        time: 1,
        width: 2,
        height: 2,
        albums: [],
      );
      final futures = List.generate(9, (_) => repo.thumbnail(asset, 64));
      await tester.pump();
      expect(requests.length, 4);
      repo.clearImages();
      for (final request in requests) {
        request.complete(Uint8List.fromList([1, 2, 3]));
      }
      await tester.pump();
      expect(await Future.wait(futures), everyElement(isNull));
      expect(
        requests.length,
        4,
        reason: 'invalidated queued jobs must not call native code',
      );
      await repo.close();
    },
  );
  testWidgets(
    'cleanup failure is observable, retained and retried on the next session',
    (tester) async {
      var releases = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'export') {
          return {
            'path': 'controlled.png',
            'bytes': 10,
            'width': 2,
            'height': 2,
            'kind': 'photo',
          };
        }
        if (call.method == 'release' && ++releases == 1) {
          throw PlatformException(code: 'cleanupFailed');
        }
        return null;
      });
      final repo = ChannelAlbumRepository(channel: channel);
      final asset = AlbumAsset(
        id: 'fixture',
        revision: 'v1',
        time: 1,
        width: 2,
        height: 2,
        albums: [],
      );
      final outputFuture = repo.prepare(
        asset,
        AlbumBudget.avatar,
        AlbumCancellation(),
        allowNetwork: false,
      );
      await tester.pump();
      final output = await outputFuture;
      final failure = expectLater(
        output.release(),
        throwsA(
          isA<AlbumFailure>().having((e) => e.code, 'code', 'cleanupFailed'),
        ),
      );
      await tester.pump();
      await failure;
      await repo.close();
      final next = ChannelAlbumRepository(channel: channel);
      await tester.pump();
      expect(releases, 2);
      await next.close();
    },
  );
}
