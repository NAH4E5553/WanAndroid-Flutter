import 'dart:async';

/// OS permission facts, never persisted as a granted flag.
enum AlbumPermission { unknown, full, limited, denied, blocked, restricted }

final class AlbumAsset {
  AlbumAsset({
    required this.id,
    required this.revision,
    required this.time,
    required this.width,
    required this.height,
    required List<String> albums,
  }) : albums = List.unmodifiable(albums);
  final String id;
  final String revision;
  final int time;
  final int width;
  final int height;
  final List<String> albums;
}

final class AlbumGroup {
  const AlbumGroup(this.id, this.name, {this.detail = ''});
  static const all = AlbumGroup('all', '所有图片');
  final String id;
  final String name;
  final String detail;
}

final class AlbumSnapshot {
  AlbumSnapshot({
    required List<AlbumAsset> assets,
    required List<AlbumGroup> groups,
  }) : assets = List.unmodifiable(assets),
       groups = List.unmodifiable(groups);
  final List<AlbumAsset> assets;
  final List<AlbumGroup> groups;
  List<AlbumAsset> inGroup(String id) => id == 'all'
      ? assets
      : assets.where((a) => a.albums.contains(id)).toList(growable: false);
}

final class AlbumBudget {
  const AlbumBudget({
    this.inputBytes = 32 * 1024 * 1024,
    this.outputBytes = 64 * 1024 * 1024,
    this.maxDimension = 8192,
    this.maxPixels = 16000000,
    this.timeout = const Duration(seconds: 60),
  });
  static const avatar = AlbumBudget(outputBytes: 32 * 1024 * 1024);
  final int inputBytes;
  final int outputBytes;
  final int maxDimension;
  final int maxPixels;
  final Duration timeout;
  Map<String, Object> toMap() => {
    'inputBytes': inputBytes,
    'outputBytes': outputBytes,
    'maxDimension': maxDimension,
    'maxPixels': maxPixels,
    'timeoutMs': timeout.inMilliseconds,
  };
}

final class AlbumCancellation {
  final Completer<void> _done = Completer<void>();
  bool get cancelled => _done.isCompleted;
  Future<void> get whenCancelled => _done.future;
  void cancel() {
    if (!cancelled) _done.complete();
  }
}

final class AlbumFailure implements Exception {
  const AlbumFailure(this.code);
  final String code;
  @override
  String toString() => 'AlbumFailure($code)';
}

/// Owns only an exported copy. Release is idempotent; a failed cleanup can retry.
final class AlbumFileLease {
  AlbumFileLease({
    required this.path,
    required this.byteLength,
    required this.width,
    required this.height,
    required this.staticKind,
    required this._release,
  });
  final String path;
  final int byteLength;
  final int width;
  final int height;
  final String staticKind;
  int get contractVersion => 1;
  String get mime => 'image/png';
  bool get upright => true;
  String get metadataPolicy => 'stripped';
  final Future<void> Function() _release;
  Future<void>? _releasing;
  bool _released = false;
  Future<void> release() async {
    if (_released) return;
    final pending = _releasing ??= _release();
    try {
      await pending;
      _released = true;
    } finally {
      if (!_released) _releasing = null;
    }
  }
}

enum AlbumResultKind {
  selected,
  cancelled,
  cameraRequested,
  systemPickerRequested,
  failed,
}

final class AlbumResult {
  const AlbumResult(this.kind, {this.lease, this.errorCode});
  final AlbumResultKind kind;
  final AlbumFileLease? lease;
  final String? errorCode;
}

/// Appearance, tuning defaults and host-owned translations; independent of Flutter.
final class AlbumPickerOptions {
  const AlbumPickerOptions({
    this.pageSize = 80,
    this.thumbnailConcurrency = 4,
    this.thumbnailBytes = 24 * 1024 * 1024,
    this.gridGap = 2,
    this.animationDuration = const Duration(milliseconds: 200),
    this.translations = const <String, String>{},
  }) : assert(pageSize > 0),
       assert(thumbnailConcurrency > 0),
       assert(thumbnailBytes > 0),
       assert(gridGap >= 0);
  final int pageSize, thumbnailConcurrency, thumbnailBytes;
  final double gridGap;
  final Duration animationDuration;
  final Map<String, String> translations;
  String text(String original) => translations[original] ?? original;
}
