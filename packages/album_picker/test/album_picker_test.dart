import 'dart:async';
import 'dart:typed_data';

import 'package:album_picker/src/data/repository/contract/album_repository.dart';
import 'package:album_picker/src/data/service/export_scheduler.dart';
import 'package:album_picker/src/features/picker/view/album_picker_screen.dart';
import 'package:album_picker/src/features/picker/view_model/album_picker_view_model.dart';
import 'package:album_picker/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AlbumFileLease lease(Future<void> Function() release) => AlbumFileLease(
  path: 'controlled-copy.png',
  byteLength: 10,
  width: 2,
  height: 2,
  staticKind: 'photo',
  release: release,
);
final assets = List.generate(
  100,
  (i) => AlbumAsset(
    id: 'asset-$i',
    revision: '1',
    time: 100 - i,
    width: 2,
    height: 2,
    albums: ['a'],
  ),
);

class FakeLibrary implements AlbumRepository {
  AlbumPermission current = AlbumPermission.full;
  int requests = 0, preparations = 0, clears = 0;
  final events = StreamController<void>.broadcast();
  Completer<AlbumFileLease>? exporting;
  AlbumCancellation? active;
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<AlbumPermission> permission({bool request = false}) async {
    if (request) requests++;
    return current;
  }

  @override
  Future<void> manageAccess() async {}
  @override
  Future<void> openSettings() async {}
  @override
  Future<AlbumSnapshot> snapshot() async => AlbumSnapshot(
    assets: assets,
    groups: [AlbumGroup.all, const AlbumGroup('a', '很长的相册名称很长的相册名称')],
  );
  @override
  Future<Uint8List?> thumbnail(AlbumAsset asset, int size) async => null;
  @override
  Future<AlbumFileLease> prepare(
    AlbumAsset asset,
    AlbumBudget budget,
    AlbumCancellation cancellation, {
    required bool allowNetwork,
  }) {
    preparations++;
    active = cancellation;
    return (exporting = Completer<AlbumFileLease>()).future;
  }

  @override
  void clearImages() {
    clears++;
  }

  @override
  Future<void> close() => events.close();
}

void main() {
  testWidgets(
    'stuck cancellation fails within five seconds, never starts second worker, recovers after real stop',
    (tester) async {
      final scheduler = ExportScheduler();
      final cancellation = AlbumCancellation();
      final work = Completer<AlbumFileLease>();
      int starts = 0, releases = 0, stops = 0;
      final first = scheduler.run(
        cancellation: cancellation,
        timeout: const Duration(seconds: 60),
        start: () {
          starts++;
          return work.future;
        },
        stop: () async {
          stops++;
        },
      );
      final firstCheck = expectLater(
        first,
        throwsA(isA<AlbumFailure>().having((e) => e.code, 'code', 'cancelled')),
      );
      cancellation.cancel();
      await tester.pump();
      await firstCheck;
      await tester.pump(const Duration(seconds: 4));
      final next = scheduler.run(
        cancellation: AlbumCancellation(),
        timeout: const Duration(seconds: 60),
        start: () {
          starts++;
          return Future.value(lease(() async {}));
        },
        stop: () async {},
      );
      final nextCheck = expectLater(
        next,
        throwsA(
          isA<AlbumFailure>().having(
            (e) => e.code,
            'code',
            'exportUnavailable',
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await nextCheck;
      expect(starts, 1);
      expect(stops, 1);
      work.complete(
        lease(() async {
          releases++;
        }),
      );
      await tester.pump();
      expect(releases, 1);
      final recovered = await scheduler.run(
        cancellation: AlbumCancellation(),
        timeout: const Duration(seconds: 60),
        start: () async {
          starts++;
          return lease(() async {});
        },
        stop: () async {},
      );
      await recovered.release();
      expect(starts, 2);
    },
  );
  testWidgets(
    'timeout rejects late successful lease and lease release retries failures',
    (tester) async {
      final scheduler = ExportScheduler();
      final work = Completer<AlbumFileLease>();
      int released = 0;
      final result = scheduler.run(
        cancellation: AlbumCancellation(),
        timeout: const Duration(seconds: 2),
        start: () => work.future,
        stop: () async {},
      );
      final check = expectLater(
        result,
        throwsA(isA<AlbumFailure>().having((e) => e.code, 'code', 'timeout')),
      );
      await tester.pump(const Duration(seconds: 2));
      await check;
      work.complete(
        lease(() async {
          released++;
        }),
      );
      await tester.pump();
      expect(released, 1);
      var attempts = 0;
      final retry = lease(() async {
        if (++attempts == 1) throw const AlbumFailure('cleanupFailed');
      });
      await expectLater(retry.release(), throwsA(isA<AlbumFailure>()));
      await retry.release();
      await retry.release();
      expect(attempts, 2);
    },
  );
  testWidgets(
    'entry and resumed only check; authorization requires explicit action',
    (tester) async {
      final repo = FakeLibrary()..current = AlbumPermission.unknown;
      final vm = AlbumPickerViewModel(repo);
      await tester.pump();
      expect(repo.requests, 0);
      vm.resumed();
      await tester.pump();
      expect(repo.requests, 0);
      await vm.authorize();
      expect(repo.requests, 1);
      vm.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'back cancels attempt in grid, second back exits, late export released',
    (tester) async {
      final repo = FakeLibrary();
      final vm = AlbumPickerViewModel(repo);
      await tester.pump();
      final selection = vm.select(assets.first);
      await tester.pump();
      expect(vm.state.busy, true);
      vm.back();
      expect(vm.state.result, null);
      expect(repo.active!.cancelled, true);
      expect(vm.state.busy, false);
      vm.back();
      expect(vm.state.result!.kind, AlbumResultKind.cancelled);
      int releases = 0;
      repo.exporting!.complete(
        lease(() async {
          releases++;
        }),
      );
      await selection;
      expect(releases, 1);
      vm.dispose();
      await tester.pump();
    },
  );
  testWidgets('permission shrink invalidates old images and selection', (
    tester,
  ) async {
    final repo = FakeLibrary();
    final vm = AlbumPickerViewModel(repo);
    await tester.pump();
    final selection = vm.select(assets.first);
    repo.current = AlbumPermission.blocked;
    repo.events.add(null);
    await tester.pump();
    expect(vm.state.snapshot, null);
    expect(repo.active!.cancelled, true);
    int releases = 0;
    repo.exporting!.complete(
      lease(() async {
        releases++;
      }),
    );
    await selection;
    expect(releases, 1);
    expect(vm.state.result, null);
    vm.dispose();
    await tester.pump();
  });
  testWidgets(
    'album scroll anchor survives switching and restores enough pages',
    (tester) async {
      final vm = AlbumPickerViewModel(FakeLibrary());
      await tester.pump();
      vm.rememberPosition(2500, assets[96].id, 5);
      vm.chooseGroup('a');
      expect(vm.restoreOffset(100), 0);
      vm.chooseGroup('all');
      expect(vm.state.limit, 160);
      expect(vm.restoreOffset(100), 2405);
      await vm.refresh();
      expect(vm.restoreOffset(100), 2405);
      vm.dispose();
      await tester.pump();
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'four columns, rotating arrow and overlay prevents photo hit at 200 percent dark=$dark',
      (tester) async {
        final repo = FakeLibrary();
        final vm = AlbumPickerViewModel(repo);
        await tester.pump();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(400, 800),
                textScaler: TextScaler.linear(2),
              ),
              child: AlbumPickerScreen(model: vm, onComplete: (_) {}),
            ),
          ),
        );
        await tester.pump();
        final grid = tester.widget<GridView>(find.byType(GridView));
        expect(
          (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          4,
        );
        vm.toggleAlbums();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
          .5,
        );
        expect(find.text('所有图片 (100)'), findsOneWidget);
        await tester.tap(find.text('所有图片 (100)'));
        await tester.pump();
        expect(repo.preparations, 0);
        expect(vm.state.expanded, false);
        vm.toggleAlbums();
        await tester.pump(const Duration(milliseconds: 100));
        vm.toggleAlbums();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
        vm.dispose();
        await tester.pump();
      },
    );
  }
}
