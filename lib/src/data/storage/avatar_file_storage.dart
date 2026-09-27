import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';

/// Directory seams so tests can run against temp layouts while production
/// resolves the real app-support/temp directories.
abstract interface class AvatarDirectories {
  Future<String> applicationSupportDirectory();
  Future<String> temporaryDirectory();
}

final class PathProviderAvatarDirectories implements AvatarDirectories {
  const PathProviderAvatarDirectories();

  @override
  Future<String> applicationSupportDirectory() async =>
      (await getApplicationSupportDirectory()).path;

  @override
  Future<String> temporaryDirectory() async =>
      (await getTemporaryDirectory()).path;
}

/// Persisted avatar index: single authority mapping `userId` → avatar file.
@immutable
final class AvatarIndexSnapshot {
  const AvatarIndexSnapshot({
    required this.writeVersion,
    required this.entries,
  });

  const AvatarIndexSnapshot.empty()
    : this(writeVersion: 0, entries: const <int, String>{});

  final int writeVersion;

  /// `userId` → avatar file name (no paths).
  final Map<int, String> entries;

  String? fileFor(int userId) => entries[userId];

  AvatarIndexSnapshot copyWith({
    int? writeVersion,
    Map<int, String>? entries,
  }) => AvatarIndexSnapshot(
    writeVersion: writeVersion ?? this.writeVersion,
    entries: entries ?? this.entries,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'writeVersion': writeVersion,
    // JSON 不支持整型键：以十进制字符串存储 userId。
    'entries': <String, String>{
      for (final MapEntry<int, String> e in entries.entries)
        e.key.toString(): e.value,
    },
  };

  /// Null when the payload is unreadable/corrupt; the caller records a
  /// sanitized diagnostic and falls back to the default avatar.
  static AvatarIndexSnapshot? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final Object? version = json['writeVersion'];
    final Object? entries = json['entries'];
    if (version is! int || entries is! Map) {
      return null;
    }
    final Map<int, String> parsed = <int, String>{};
    for (final MapEntry<Object?, Object?> e in entries.entries) {
      final Object? key = e.key is int
          ? e.key
          : int.tryParse(e.key as String? ?? '');
      if (key is! int || e.value is! String) {
        return null;
      }
      parsed[key] = e.value as String;
    }
    return AvatarIndexSnapshot(writeVersion: version, entries: parsed);
  }
}

/// File-backed avatar storage: avatar files, the versioned JSON index and
/// the pending-operation record. All writes use write-flush-rename inside the
/// destination directory so a process kill can never leave a half-written
/// index or image behind.
final class AvatarFileStorage {
  AvatarFileStorage({required this._directories, this._excludeFromBackup});

  /// 目录备份排除标记未能应用（iOS）时的诊断开关由仓储读取。

  /// 测试注入：为 true 时下一次索引写入抛出 FileSystemException。
  @visibleForTesting
  bool failIndexWrites = false;

  /// 目录备份排除标记未能应用（iOS）：由仓储在 initialize 中诊断。
  bool backupExclusionFailed = false;

  static const String _indexFileName = 'avatar_index.json';
  static const String _pendingFileName = 'pending_avatar_operation.json';
  static const String _avatarDirName = 'avatars';

  final AvatarDirectories _directories;
  final Future<bool> Function(String directory)? _excludeFromBackup;
  String? _avatarDirectoryPath;
  String? _candidateDirectoryPath;
  int _uniqueCounter = 0;

  Future<String> avatarDirectory() async {
    final String existing = _avatarDirectoryPath ?? '';
    if (existing.isNotEmpty) {
      return existing;
    }
    final Directory dir = Directory(
      p.join(await _directories.applicationSupportDirectory(), _avatarDirName),
    );
    await dir.create(recursive: true);
    try {
      final bool excluded = await _excludeFromBackup?.call(dir.path) ?? true;
      backupExclusionFailed = !excluded;
    } on Object {
      backupExclusionFailed = true;
    }
    _avatarDirectoryPath = dir.path;
    return dir.path;
  }

  Future<String> candidateDirectory() async {
    final String existing = _candidateDirectoryPath ?? '';
    if (existing.isNotEmpty) {
      return existing;
    }
    final Directory dir = Directory(
      p.join(await _directories.temporaryDirectory(), 'avatar_candidate'),
    );
    await dir.create(recursive: true);
    _candidateDirectoryPath = dir.path;
    return dir.path;
  }

  Future<String> indexFilePath() async =>
      p.join(await avatarDirectory(), _indexFileName);

  Future<String> pendingFilePath() async =>
      p.join(await avatarDirectory(), _pendingFileName);

  Future<String> newAvatarFileName(int userId) async =>
      'avatar_${userId}_${_uniqueSuffix()}.png';

  Future<String> newTempFilePathInAvatarDirectory() async =>
      '${(await avatarDirectory())}${p.separator}writing_${_uniqueSuffix()}.tmp';

  Future<String> newCandidateFilePath() async =>
      p.join(await candidateDirectory(), 'candidate_${_uniqueSuffix()}.bin');

  Future<String> avatarFilePath(String fileName) async =>
      p.join(await avatarDirectory(), fileName);

  /// Writes bytes durably: temp file + flush + rename inside the same
  /// directory, so the destination path only ever holds a complete file.
  Future<void> writeBytesAtomically(String destination, List<int> bytes) async {
    final File temp = File('$destination.${_uniqueSuffix()}.tmp');
    final RandomAccessFile handle = await temp.open(mode: FileMode.write);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
    await temp.rename(destination);
  }

  Future<Uint8List?> readBytes(String path) async {
    final File file = File(path);
    if (!await file.exists()) {
      return null;
    }
    return await file.readAsBytes();
  }

  Future<bool> fileExists(String path) async => File(path).exists();

  Future<void> deleteFile(String path) async {
    final File file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<List<String>> listAvatarFileNames() async {
    final Directory dir = Directory(await avatarDirectory());
    final List<FileSystemEntity> entities = await dir.list().toList();
    return entities
        .whereType<File>()
        .map((File file) => p.basename(file.path))
        .where((String name) => name.endsWith('.png') && !name.endsWith('.tmp'))
        .toList();
  }

  /// 目录内全部文件名（含临时/损坏文件），供孤儿清理使用。
  Future<List<String>> listAllFileNames() async {
    final Directory dir = Directory(await avatarDirectory());
    final List<FileSystemEntity> entities = await dir.list().toList();
    return entities
        .whereType<File>()
        .map((File file) => p.basename(file.path))
        .toList();
  }

  Future<AvatarIndexSnapshot?> readIndex() async {
    final File file = File(await indexFilePath());
    if (!await file.exists()) {
      return null;
    }
    try {
      final String contents = await file.readAsString();
      return AvatarIndexSnapshot.fromJson(jsonDecode(contents));
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> writeIndex(AvatarIndexSnapshot index) async {
    if (failIndexWrites) {
      failIndexWrites = false;
      throw const FileSystemException('avatar index write injected failure');
    }
    final String encoded = const JsonEncoder.withIndent('  ')
        .convert(index.toJson());
    await writeBytesAtomically(await indexFilePath(), utf8.encode(encoded));
  }

  Future<PendingAvatarOperation?> readPendingOperation() async {
    final File file = File(await pendingFilePath());
    if (!await file.exists()) {
      return null;
    }
    try {
      final String contents = await file.readAsString();
      return PendingAvatarOperation.fromJson(jsonDecode(contents));
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> writePendingOperation(PendingAvatarOperation? operation) async {
    final String destination = await pendingFilePath();
    if (operation == null) {
      await deleteFile(destination);
      return;
    }
    final String encoded = const JsonEncoder.withIndent('  ')
        .convert(operation.toJson());
    await writeBytesAtomically(destination, utf8.encode(encoded));
  }

  String _uniqueSuffix() {
    final int counter = _uniqueCounter++;
    final int stamp = DateTime.now().microsecondsSinceEpoch;
    final int random = Random().nextInt(0xFFFF);
    return '$stamp${counter}_$random';
  }
}
