import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_storage.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';

void main() {
  test('loads a persisted selection', () async {
    final _ImmediateThemeStorage storage = _ImmediateThemeStorage(
      saved: (palette: WanPalette.warmAmber, mode: ThemeMode.dark),
    );
    final ThemeController controller = ThemeController(preferences: storage);

    await controller.load();

    expect(controller.loadStatus, ThemeLoadStatus.ready);
    expect(controller.palette, WanPalette.warmAmber);
    expect(controller.mode, ThemeMode.dark);
  });

  test('read failure keeps safe defaults and remains observable', () async {
    final ThemeController controller = ThemeController(
      preferences: _ReadFailingThemeStorage(),
    );

    await controller.load();

    expect(controller.loadStatus, ThemeLoadStatus.readFailed);
    expect(controller.palette, WanPalette.slateBlue);
    expect(controller.mode, ThemeMode.system);
  });

  test('rapid selections serialize writes and persist the latest', () async {
    final _ControllableThemeStorage storage = _ControllableThemeStorage();
    final ThemeController controller = ThemeController(preferences: storage);
    await controller.load();

    final Future<ThemeApplyResult> first = controller.apply(
      WanPalette.inkTeal,
      ThemeMode.system,
    );
    final _PendingStorageWrite firstWrite = await storage.nextWrite();
    final Future<ThemeApplyResult> latest = controller.apply(
      WanPalette.berryRose,
      ThemeMode.dark,
    );

    expect(controller.palette, WanPalette.berryRose);
    expect(controller.mode, ThemeMode.dark);
    expect(controller.saving, isTrue);
    expect(storage.writeCount, 1);

    firstWrite.succeed();
    final _PendingStorageWrite latestWrite = await storage.nextWrite();
    expect(latestWrite.selection.palette, WanPalette.berryRose);
    expect(latestWrite.selection.mode, ThemeMode.dark);
    latestWrite.succeed();

    expect(await first, ThemeApplyResult.superseded);
    expect(await latest, ThemeApplyResult.applied);
    expect(controller.palette, WanPalette.berryRose);
    expect(controller.mode, ThemeMode.dark);
    expect(controller.saving, isFalse);
  });

  test('an older failed write cannot roll back a newer selection', () async {
    final _ControllableThemeStorage storage = _ControllableThemeStorage();
    final ThemeController controller = ThemeController(preferences: storage);
    await controller.load();

    final Future<ThemeApplyResult> first = controller.apply(
      WanPalette.inkTeal,
      ThemeMode.system,
    );
    final _PendingStorageWrite firstWrite = await storage.nextWrite();
    final Future<ThemeApplyResult> latest = controller.apply(
      WanPalette.warmAmber,
      ThemeMode.light,
    );
    firstWrite.fail();
    final _PendingStorageWrite latestWrite = await storage.nextWrite();
    latestWrite.succeed();

    expect(await first, ThemeApplyResult.superseded);
    expect(await latest, ThemeApplyResult.applied);
    expect(controller.palette, WanPalette.warmAmber);
    expect(controller.mode, ThemeMode.light);
    expect(controller.saveFailed, isFalse);
  });

  test('latest failed write restores the last persisted selection', () async {
    final _ControllableThemeStorage storage = _ControllableThemeStorage();
    final ThemeController controller = ThemeController(preferences: storage);
    await controller.load();

    final Future<ThemeApplyResult> apply = controller.apply(
      WanPalette.berryRose,
      ThemeMode.dark,
    );
    final _PendingStorageWrite write = await storage.nextWrite();
    write.fail();

    expect(await apply, ThemeApplyResult.failed);
    expect(controller.palette, WanPalette.slateBlue);
    expect(controller.mode, ThemeMode.system);
    expect(controller.saveFailed, isTrue);
    expect(controller.saving, isFalse);
  });
}

final class _ImmediateThemeStorage implements ThemeStorage {
  _ImmediateThemeStorage({this.saved});

  final ThemeSelection? saved;

  @override
  Future<ThemeSelection?> read() async => saved;

  @override
  Future<void> write(WanPalette palette, ThemeMode mode) async {}
}

final class _ReadFailingThemeStorage implements ThemeStorage {
  @override
  Future<ThemeSelection?> read() async => throw StateError('fixture');

  @override
  Future<void> write(WanPalette palette, ThemeMode mode) async {}
}

final class _ControllableThemeStorage implements ThemeStorage {
  final Queue<_PendingStorageWrite> _writes = Queue<_PendingStorageWrite>();
  final Queue<Completer<_PendingStorageWrite>> _waiters =
      Queue<Completer<_PendingStorageWrite>>();
  int writeCount = 0;

  @override
  Future<ThemeSelection?> read() async => null;

  @override
  Future<void> write(WanPalette palette, ThemeMode mode) {
    writeCount += 1;
    final _PendingStorageWrite write = _PendingStorageWrite((
      palette: palette,
      mode: mode,
    ));
    if (_waiters.isEmpty) {
      _writes.add(write);
    } else {
      _waiters.removeFirst().complete(write);
    }
    return write.completion.future;
  }

  Future<_PendingStorageWrite> nextWrite() {
    if (_writes.isNotEmpty) {
      return Future<_PendingStorageWrite>.value(_writes.removeFirst());
    }
    final Completer<_PendingStorageWrite> waiter =
        Completer<_PendingStorageWrite>();
    _waiters.add(waiter);
    return waiter.future;
  }
}

final class _PendingStorageWrite {
  _PendingStorageWrite(this.selection);

  final ThemeSelection selection;
  final Completer<void> completion = Completer<void>();

  void succeed() => completion.complete();

  void fail() => completion.completeError(StateError('fixture write failure'));
}
