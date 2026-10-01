import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../../../model/album_models.dart';
import '../../service/export_scheduler.dart';
import '../contract/album_repository.dart';

final class ChannelAlbumRepository implements AlbumRepository {
  ChannelAlbumRepository({
    MethodChannel? channel,
    this.options = const AlbumPickerOptions(),
  }) : _channel = channel ?? const MethodChannel('dev.portable.album_picker') {
    for (final retry in _pendingCleanup.values.toList()) {
      unawaited(retry().catchError((Object _) {}));
    }
  }
  static final _scheduler = ExportScheduler();
  static final Stream<void> _events = const EventChannel(
    'dev.portable.album_picker/changes',
  ).receiveBroadcastStream().map<void>((_) {});
  final MethodChannel _channel;
  final AlbumPickerOptions options;
  final _cache = <String, (Uint8List, int)>{};
  final _waiting = Queue<Completer<void>>();
  static final _pendingCleanup = <String, Future<void> Function()>{};
  final String _session =
      '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
  int _serial = 0, _epoch = 0, _bytes = 0, _concurrent = 0;
  bool _closed = false;
  @override
  Stream<void> get changes => _events;
  Future<T?> _call<T>(String method, [Map<String, Object>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw AlbumFailure(e.code);
    } on MissingPluginException {
      throw const AlbumFailure('unsupported');
    }
  }

  @override
  Future<AlbumPermission> permission({bool request = false}) async {
    final value = await _call<String>(request ? 'request' : 'permission');
    return AlbumPermission.values.firstWhere(
      (v) => v.name == value,
      orElse: () => AlbumPermission.unknown,
    );
  }

  @override
  Future<void> manageAccess() async {
    await _call<void>('manage');
  }

  @override
  Future<void> openSettings() async {
    await _call<void>('settings');
  }

  @override
  Future<AlbumSnapshot> snapshot() async {
    final raw = (await _call<Map<Object?, Object?>>('snapshot'))!;
    final assets = <String, AlbumAsset>{};
    for (final item in raw['assets']! as List<Object?>) {
      final m = item! as Map<Object?, Object?>;
      final asset = AlbumAsset(
        id: m['id']! as String,
        revision: m['revision']! as String,
        time: m['time']! as int,
        width: m['width']! as int,
        height: m['height']! as int,
        albums: (m['albums']! as List<Object?>).cast<String>(),
      );
      assets[asset.id] = asset;
    }
    final ordered = assets.values.toList()
      ..sort((a, b) {
        final time = b.time.compareTo(a.time);
        return time == 0 ? a.id.compareTo(b.id) : time;
      });
    final groups = <AlbumGroup>[];
    for (final item in raw['groups']! as List<Object?>) {
      final m = item! as Map<Object?, Object?>;
      final id = m['id']! as String;
      if (ordered.any((a) => a.albums.contains(id))) {
        groups.add(
          AlbumGroup(
            id,
            m['name']! as String,
            detail: m['detail'] as String? ?? '',
          ),
        );
      }
    }
    int newest(String id) =>
        ordered.firstWhere((a) => a.albums.contains(id)).time;
    groups.sort((a, b) {
      final c = newest(b.id).compareTo(newest(a.id));
      return c == 0 ? a.id.compareTo(b.id) : c;
    });
    return AlbumSnapshot(assets: ordered, groups: [AlbumGroup.all, ...groups]);
  }

  @override
  Future<Uint8List?> thumbnail(AlbumAsset asset, int size) async {
    final epoch = _epoch;
    final bounded = size.clamp(32, 512);
    final key = '$epoch:${asset.id}:${asset.revision}:$bounded';
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached.$1;
    }
    if (_concurrent >= options.thumbnailConcurrency) {
      final waiter = Completer<void>();
      _waiting.add(waiter);
      await waiter.future;
    } else {
      _concurrent++;
    }
    try {
      if (_closed || epoch != _epoch) return null;
      final bytes = await _call<Uint8List>('thumbnail', {
        'id': asset.id,
        'size': bounded,
        'session': _session,
      });
      if (_closed || epoch != _epoch || bytes == null) return null;
      final cost = bounded * bounded * 4 + bytes.length;
      final replaced = _cache.remove(key);
      if (replaced != null) _bytes -= replaced.$2;
      _cache[key] = (bytes, cost);
      _bytes += cost;
      while (_bytes > options.thumbnailBytes && _cache.isNotEmpty) {
        final removed = _cache.remove(_cache.keys.first)!;
        _bytes -= removed.$2;
        unawaited(MemoryImage(removed.$1).evict());
      }
      return bytes;
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _concurrent--;
      }
    }
  }

  @override
  Future<AlbumFileLease> prepare(
    AlbumAsset asset,
    AlbumBudget budget,
    AlbumCancellation cancellation, {
    required bool allowNetwork,
  }) {
    final token = '${_session}_${++_serial}';
    return _scheduler.run(
      cancellation: cancellation,
      timeout: budget.timeout,
      stop: () async {
        await _call<void>('cancel', {'token': token});
      },
      start: () async {
        if (_closed) throw const AlbumFailure('cancelled');
        final raw = (await _call<Map<Object?, Object?>>('export', {
          'id': asset.id,
          'revision': asset.revision,
          'token': token,
          'allowNetwork': allowNetwork,
          ...budget.toMap(),
        }))!;
        Future<void> release() async {
          try {
            await _call<void>('release', {
              'token': token,
            }).timeout(const Duration(seconds: 5));
            _pendingCleanup.remove(token);
          } catch (_) {
            _pendingCleanup[token] = release;
            debugPrint('album_picker: cleanupFailed; retry queued');
            throw const AlbumFailure('cleanupFailed');
          }
        }

        return AlbumFileLease(
          path: raw['path']! as String,
          byteLength: raw['bytes']! as int,
          width: raw['width']! as int,
          height: raw['height']! as int,
          staticKind: raw['kind']! as String,
          release: release,
        );
      },
    );
  }

  @override
  void clearImages() {
    _epoch++;
    for (final value in _cache.values) {
      unawaited(MemoryImage(value.$1).evict());
    }
    _cache.clear();
    _bytes = 0;
    unawaited(
      _call<void>('clearThumbnails', {
        'session': _session,
      }).catchError((Object _) {}),
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
    clearImages();
  }
}
