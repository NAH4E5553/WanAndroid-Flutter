import 'dart:async';
import 'dart:io';

import 'package:album_picker/models.dart';
import 'package:album_picker/src/data/repository/contract/album_repository.dart';
import 'package:album_picker/src/data/repository/implementation/channel_album_repository.dart';
import 'package:album_picker/src/features/picker/view/album_picker_screen.dart';
import 'package:album_picker/src/features/picker/view_model/album_picker_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const fixture = MethodChannel('dev.portable.album_fixture');
Future<void> phase(String value) =>
    fixture.invokeMethod('phase', {'value': value});
Future<void> until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 900; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (ready()) return;
  }
  fail('Controlled device phase timed out');
}

// Only metadata comes from exact fixture URI queries. Permissions, thumbnails
// and exports use the actual production native gateway. Never call the broad
// personal-library snapshot method as automated evidence.
class ControlledLibrary implements AlbumRepository {
  final native = ChannelAlbumRepository();
  int requests = 0;
  bool holdExport = false;
  bool managementComplete = false;
  @override
  Stream<void> get changes => native.changes;
  @override
  Future<AlbumPermission> permission({bool request = false}) {
    if (request) requests++;
    return native.permission(request: request);
  }

  @override
  Future<AlbumSnapshot> snapshot() async {
    final rows = (await fixture.invokeListMethod<Object?>('describe'))!;
    final groups = <String, AlbumGroup>{};
    final assets = <AlbumAsset>[];
    for (final row in rows) {
      final m = row! as Map<Object?, Object?>;
      final id = m['group']! as String;
      groups[id] = AlbumGroup(
        id,
        (m['name']! as String).endsWith('_A') ? '测试相册 A' : '测试相册 B',
      );
      assets.add(
        AlbumAsset(
          id: m['id']! as String,
          revision: m['revision']! as String,
          time: 0,
          width: m['width']! as int,
          height: m['height']! as int,
          albums: [id],
        ),
      );
    }
    return AlbumSnapshot(
      assets: assets,
      groups: [AlbumGroup.all, ...groups.values],
    );
  }

  @override
  Future<Uint8List?> thumbnail(AlbumAsset asset, int size) =>
      native.thumbnail(asset, size);
  @override
  Future<AlbumFileLease> prepare(
    AlbumAsset asset,
    AlbumBudget budget,
    AlbumCancellation cancellation, {
    required bool allowNetwork,
  }) async {
    if (holdExport) {
      await cancellation.whenCancelled;
      throw const AlbumFailure('cancelled');
    }
    return native.prepare(
      asset,
      budget,
      cancellation,
      allowNetwork: allowNetwork,
    );
  }

  @override
  Future<void> manageAccess() async {
    managementComplete = false;
    await native.manageAccess();
    managementComplete = true;
  }

  @override
  Future<void> openSettings() => native.openSettings();
  @override
  void clearImages() => native.clearImages();
  @override
  Future<void> close() => native.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    expect(
      Platform.isAndroid &&
          const bool.fromEnvironment('ALBUM_CONTROLLED_ANDROID'),
      isTrue,
    );
    await fixture.invokeMethod<void>('seed');
  });
  tearDownAll(() async {
    expect(await fixture.invokeMethod<int>('cleanup'), 0);
    await phase('complete_clean');
  });
  testWidgets(
    'Android real permission denial then grant, no automatic request',
    (tester) async {
      final repo = ControlledLibrary();
      final vm = AlbumPickerViewModel(repo);
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AlbumPickerScreen(model: vm, onComplete: (_) {}),
        ),
      );
      await until(tester, () => !vm.state.loading);
      expect(vm.state.permission, AlbumPermission.unknown);
      expect(repo.requests, 0);
      await phase('await_deny');
      await tester.tap(find.text('授权照片访问'));
      await until(
        tester,
        () =>
            !vm.state.loading && vm.state.permission != AlbumPermission.unknown,
      );
      expect(vm.state.permission, AlbumPermission.denied);
      expect(repo.requests, 1);
      const checkLimited = bool.fromEnvironment('ALBUM_TEST_LIMITED');
      await phase(checkLimited ? 'await_limited' : 'await_grant');
      await tester.tap(find.text('授权照片访问'));
      await until(
        tester,
        () =>
            !vm.state.loading &&
            vm.state.permission ==
                (checkLimited ? AlbumPermission.limited : AlbumPermission.full),
      );
      if (checkLimited) {
        expect(find.text('仅显示已授权的照片'), findsOneWidget);
        expect(find.text('管理可访问照片'), findsOneWidget);
        await phase('await_reselect');
        await tester.tap(find.text('管理可访问照片'));
        await until(
          tester,
          () =>
              repo.managementComplete &&
              !vm.state.loading &&
              vm.state.permission == AlbumPermission.limited,
        );
      }
      expect(repo.requests, 2);
      expect(vm.state.assets.length, 8);
      await phase('permission_passed');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'Android native thumbnails, PNG limits, source preservation and stale resource rejection',
    (tester) async {
      final repo = ControlledLibrary();
      try {
        expect(
          await repo.permission(),
          const bool.fromEnvironment('ALBUM_TEST_LIMITED')
              ? AlbumPermission.limited
              : AlbumPermission.full,
        );
        final snapshot = await repo.snapshot();
        expect(snapshot.assets.length, 8);
        expect(snapshot.groups.length, 3);
        final asset = snapshot.assets.first;
        final thumbnail = await repo.thumbnail(asset, 128);
        expect(thumbnail, isNotNull);
        final output = await repo.prepare(
          asset,
          AlbumBudget.avatar,
          AlbumCancellation(),
          allowNetwork: false,
        );
        final file = File(output.path);
        final bytes = await file.readAsBytes();
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        expect((output.width, output.height), (96, 64));
        expect(output.byteLength, bytes.length);
        final data = ByteData.sublistView(bytes);
        var offset = 8;
        while (offset + 12 <= bytes.length) {
          final length = data.getUint32(offset);
          expect(
            ['eXIf', 'tEXt', 'iTXt', 'zTXt'].contains(
              String.fromCharCodes(bytes.sublist(offset + 4, offset + 8)),
            ),
            isFalse,
          );
          offset += length + 12;
        }
        await output.release();
        await output.release();
        expect(await file.exists(), isFalse);
        expect((await repo.snapshot()).assets.length, 8);
        for (final budget in [
          const AlbumBudget(inputBytes: 1),
          const AlbumBudget(outputBytes: 1),
          const AlbumBudget(maxPixels: 1),
        ]) {
          await expectLater(
            repo.prepare(
              asset,
              budget,
              AlbumCancellation(),
              allowNetwork: false,
            ),
            throwsA(
              isA<AlbumFailure>().having(
                (e) => e.code,
                'code',
                'budgetExceeded',
              ),
            ),
          );
        }
        final retry = await repo.prepare(
          asset,
          AlbumBudget.avatar,
          AlbumCancellation(),
          allowNetwork: false,
        );
        await retry.release();
        await fixture.invokeMethod<void>('deleteFirst');
        await expectLater(
          repo.prepare(
            asset,
            AlbumBudget.avatar,
            AlbumCancellation(),
            allowNetwork: false,
          ),
          throwsA(
            isA<AlbumFailure>().having(
              (e) => e.code,
              'code',
              'resourceChanged',
            ),
          ),
        );
        expect((await repo.snapshot()).assets.length, 7);
        await phase('native_passed');
      } finally {
        await repo.close();
      }
    },
  );

  testWidgets(
    'Android four-column group switching, actual Back cancels preparation then exits',
    (tester) async {
      final repo = ControlledLibrary();
      final vm = AlbumPickerViewModel(repo);
      addTearDown(vm.dispose);
      AlbumResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: AlbumPickerScreen(
            model: vm,
            onComplete: (value) => result = value,
          ),
        ),
      );
      await until(tester, () => !vm.state.loading);
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        4,
      );
      await tester.tap(find.text('所有图片'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('所有图片 (7)'), findsOneWidget);
      await tester.tap(find.text('测试相册 B (4)'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(vm.state.assets.length, 4);
      expect(find.text('测试相册 B'), findsOneWidget);
      expect(vm.state.expanded, false);
      repo.holdExport = true;
      unawaited(vm.select(vm.state.assets.first));
      await tester.pump();
      expect(vm.state.busy, true);
      await phase('await_cancel_back');
      await until(tester, () => !vm.state.busy);
      expect(result, isNull);
      expect(vm.state.assets.length, 4);
      await phase('await_exit_back');
      await until(tester, () => result != null);
      expect(result!.kind, AlbumResultKind.cancelled);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await phase('ui_passed');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
