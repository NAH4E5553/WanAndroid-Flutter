import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:wanandroid_flutter/src/core/theme/theme_storage.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';

enum ThemeLoadStatus { loading, ready, readFailed }

enum ThemeApplyResult { applied, failed, superseded, ignored }

/// Applies theme selections immediately, persists them, and rolls the visible
/// state back when persistence fails. Read failures keep defaults but surface
/// [ThemeLoadStatus.readFailed] so the UI can say defaults are in use.
class ThemeController extends ChangeNotifier {
  ThemeController({required this._preferences});

  final ThemeStorage _preferences;

  ThemeSelection _persisted = (
    palette: WanPalette.slateBlue,
    mode: ThemeMode.system,
  );
  _ThemeWriteRequest? _pendingWrite;
  Future<void>? _writeLoop;

  ThemeLoadStatus loadStatus = ThemeLoadStatus.loading;
  WanPalette palette = WanPalette.slateBlue;
  ThemeMode mode = ThemeMode.system;
  bool saving = false;
  bool saveFailed = false;

  bool get ready => loadStatus != ThemeLoadStatus.loading;

  Future<void> load() async {
    try {
      final ThemeSelection? saved = await _preferences.read();
      if (saved != null) {
        palette = saved.palette;
        mode = saved.mode;
        _persisted = saved;
      }
      loadStatus = ThemeLoadStatus.ready;
    } on Object {
      loadStatus = ThemeLoadStatus.readFailed;
    }
    notifyListeners();
  }

  /// Applies selections immediately and serializes writes. While a write is in
  /// flight, newer selections replace the queued value so the latest user
  /// intent is always the final value persisted.
  Future<ThemeApplyResult> apply(WanPalette newPalette, ThemeMode newMode) {
    if (!ready) {
      return Future<ThemeApplyResult>.value(ThemeApplyResult.ignored);
    }
    if (palette == newPalette && mode == newMode) {
      return Future<ThemeApplyResult>.value(ThemeApplyResult.ignored);
    }

    final _ThemeWriteRequest request = _ThemeWriteRequest((
      palette: newPalette,
      mode: newMode,
    ));
    _pendingWrite?.complete(ThemeApplyResult.superseded);
    _pendingWrite = request;
    saveFailed = false;
    saving = true;
    palette = newPalette;
    mode = newMode;
    notifyListeners();

    _writeLoop ??= _drainWrites();
    return request.result;
  }

  Future<void> _drainWrites() async {
    try {
      while (_pendingWrite != null) {
        final _ThemeWriteRequest request = _pendingWrite!;
        _pendingWrite = null;
        try {
          await _preferences.write(
            request.selection.palette,
            request.selection.mode,
          );
        } on Object {
          if (_pendingWrite != null) {
            request.complete(ThemeApplyResult.superseded);
            continue;
          }
          palette = _persisted.palette;
          mode = _persisted.mode;
          saving = false;
          saveFailed = true;
          request.complete(ThemeApplyResult.failed);
          notifyListeners();
          return;
        }

        _persisted = request.selection;
        if (_pendingWrite != null) {
          request.complete(ThemeApplyResult.superseded);
          continue;
        }
        saving = false;
        saveFailed = false;
        request.complete(ThemeApplyResult.applied);
        notifyListeners();
      }
    } finally {
      _writeLoop = null;
      if (_pendingWrite != null) {
        _writeLoop = _drainWrites();
      }
    }
  }
}

final class _ThemeWriteRequest {
  _ThemeWriteRequest(this.selection);

  final ThemeSelection selection;
  final Completer<ThemeApplyResult> _completion = Completer<ThemeApplyResult>();

  Future<ThemeApplyResult> get result => _completion.future;

  void complete(ThemeApplyResult result) {
    if (!_completion.isCompleted) {
      _completion.complete(result);
    }
  }
}
