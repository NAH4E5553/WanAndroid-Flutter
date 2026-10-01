import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/avatar_repository.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_file_storage.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_gallery_gateway.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_image_normalization_gateway.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_image_processor.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_image_source_gateway.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';

/// Single authority for the local avatar. All writes funnel through one
/// serial queue guarded by a monotonic write version; every operation
/// re-validates the `userId + accountVersionKey` identity it was given, so
/// results that outlive their session are always dropped.
final class DefaultAvatarRepository implements AvatarRepository {
  DefaultAvatarRepository({
    required this._authRepository,
    required this._sourceGateway,
    required this._galleryGateway,
    required this._normalizationGateway,
    required this._processor,
    required this._storage,
    DateTime Function()? now,
    this._diagnostic,
  }) : _now = now ?? DateTime.now {
    _authRepository.addListener(_handleSessionChanged);
  }

  static const Duration pendingTtl = Duration(hours: 24);

  final AuthRepository _authRepository;
  final AvatarImageSourceGateway _sourceGateway;
  final AvatarGalleryGateway _galleryGateway;
  final AvatarImageNormalizationGateway _normalizationGateway;
  final AvatarImageProcessor _processor;
  final AvatarFileStorage _storage;
  final DateTime Function() _now;
  final void Function(String message)? _diagnostic;

  AvatarIndexSnapshot _index = const AvatarIndexSnapshot.empty();
  int _writeVersion = 0;
  String? _avatarDirectoryPath;
  _Candidate? _candidate;
  bool _committing = false;
  bool _savingToGallery = false;
  bool _picking = false;

  /// 选图会话令牌：discardCandidate 使在途选图结果失效（页面销毁后迟到的
  /// ready 不再留下候选）。
  int _pickSession = 0;
  bool _pendingAtStartup = false;
  bool _recoveryReady = false;
  final List<void Function()> _listeners = <void Function()>[];

  /// One serial entry for every durable write; later intents wait, and an
  /// earlier failure never leaks into a later operation.
  Future<void> _tail = Future<void>.value();

  /// Pending-operation writes also serialize independently. This matters for
  /// route disposal: its unawaited clear must finish before a newly opened
  /// viewer can persist a replacement operation.
  Future<void> _pendingTail = Future<void>.value();

  @override
  void addListener(void Function() listener) => _listeners.add(listener);

  @override
  void removeListener(void Function() listener) => _listeners.remove(listener);

  @override
  AvatarStateView view() {
    final AuthStateView session = _authRepository.view();
    final int? userId = session.userId;
    final bool editable =
        session.authenticated &&
        !session.loading &&
        !session.unverified &&
        !session.expiredNotice &&
        !session.storageNotice &&
        session.accountVersionKey != null;
    final String? entry = userId == null ? null : _index.fileFor(userId);
    final bool candidateMine =
        _candidate != null && userId != null && _candidate!.userId == userId;
    return AvatarStateView(
      userId: userId,
      editable: editable,
      customAvailable: entry != null,
      customAvatarPath: entry == null ? null : _pathFor(entry),
      candidateReady: candidateMine,
      candidatePath: candidateMine ? _candidate!.path : null,
      committing: _committing,
      savingToGallery: _savingToGallery,
      recoveryReady: _recoveryReady,
    );
  }

  /// Loads the persisted index, clears crash orphans and records whether a
  /// pending external operation survived the process. Called once by the
  /// composition root before any page reads the repository.
  Future<void> initialize() => _enqueue(() async {
    final PendingAvatarOperation? pendingAtStartup = await _storage
        .readPendingOperation();
    _pendingAtStartup = pendingAtStartup != null;
    final AvatarIndexSnapshot? stored = await _storage.readIndex();
    if (stored == null) {
      _diagnostic?.call(
        'avatar index missing or corrupt; default avatar active',
      );
      _index = const AvatarIndexSnapshot.empty();
      _writeVersion = 0;
    } else {
      _index = stored;
      _writeVersion = stored.writeVersion;
    }
    _avatarDirectoryPath = await _storage.avatarDirectory();
    if (_storage.backupExclusionFailed) {
      _diagnostic?.call('avatar directory backup exclusion failed');
    }
    await _cleanupOrphans();
    _notify();
  });

  @override
  bool hasPendingOperation() => _pendingAtStartup;

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final Future<T> result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<AvatarCandidateStart> startCandidate({
    required AvatarSource source,
    required AvatarIdentity identity,
  }) async {
    if (!_identityMatches(identity)) {
      return const AvatarCandidateStart.identityChanged();
    }
    // Single-flight: a second concurrent trigger must not overwrite the
    // single pending record or race the first external page.
    if (_picking) {
      return const AvatarCandidateStart.busy();
    }
    _picking = true;
    try {
      return await _startCandidate(source, identity);
    } finally {
      _picking = false;
    }
  }

  Future<AvatarCandidateStart> _startCandidate(
    AvatarSource source,
    AvatarIdentity identity,
  ) async {
    // Latest intent wins: a leftover candidate (defensive) or stale pending
    // record never blocks a new external operation.
    if (_candidate != null) {
      discardCandidate();
    }
    final int session = ++_pickSession;
    final PendingAvatarOperation operation = PendingAvatarOperation(
      operationId: _uniqueId(),
      userId: identity.userId,
      source: source,
      createdAt: _now(),
    );
    try {
      await _writePendingOperation(operation);
    } on Object {
      return const AvatarCandidateStart.failed();
    }
    if (session != _pickSession || !_identityMatches(identity)) {
      await _clearPendingOperation();
      return session != _pickSession
          ? const AvatarCandidateStart.cancelled()
          : const AvatarCandidateStart.identityChanged();
    }
    final AvatarPickOutcome outcome = await _sourceGateway.pick(source: source);
    // The external page returned; the session may have moved on meanwhile.
    if (session != _pickSession) {
      // 会话已被失效（页面销毁/被新意图取代）：迟到结果丢弃，不留候选。
      _deletePickerArtifact(outcome);
      await _clearPendingOperation();
      return const AvatarCandidateStart.cancelled();
    }
    if (!_identityMatches(identity)) {
      await _clearPendingOperation();
      _deletePickerArtifact(outcome);
      return const AvatarCandidateStart.identityChanged();
    }
    switch (outcome.status) {
      case AvatarPickStatus.cancelled:
        await _clearPendingOperation();
        return const AvatarCandidateStart.cancelled();
      case AvatarPickStatus.unavailable:
        await _clearPendingOperation();
        return const AvatarCandidateStart.unavailable();
      case AvatarPickStatus.ready:
        final String pickedPath = outcome.copiedPath!;
        String? candidatePath;
        try {
          // 损坏/超大候选不得进入调整页。文件大小、边长和总像素预算在
          // 原生完整解码前完成，候选随后统一转成已应用 EXIF 的 PNG。
          await _processor.ensureDecodable(
            path: pickedPath,
            maxDimension: UiAvatarImageProcessor.maxSourceDimension,
            maxPixelCount: UiAvatarImageProcessor.maxSourcePixelCount,
            maxFileBytes: UiAvatarImageProcessor.maxSourceFileBytes,
          );
          if (!_candidateOperationMatches(session, identity)) {
            await _clearPendingOperation();
            _deletePickerArtifact(outcome);
            return _candidateStatusAfterWait(session, identity);
          }
          candidatePath = await _storage.newCandidateFilePath();
          await _normalizationGateway.normalizeToPng(
            sourcePath: pickedPath,
            destinationPath: candidatePath,
            maxDimension: UiAvatarImageProcessor.maxSourceDimension,
            maxPixelCount: UiAvatarImageProcessor.maxSourcePixelCount,
            maxFileBytes: UiAvatarImageProcessor.maxSourceFileBytes,
          );
          await _processor.ensureDecodable(
            path: candidatePath,
            maxDimension: UiAvatarImageProcessor.maxSourceDimension,
            maxPixelCount: UiAvatarImageProcessor.maxSourcePixelCount,
            maxFileBytes: UiAvatarImageProcessor.maxSourceFileBytes,
          );
          if (!_candidateOperationMatches(session, identity)) {
            await _storage.deleteFile(candidatePath);
            await _clearPendingOperation();
            _deletePickerArtifact(outcome);
            return _candidateStatusAfterWait(session, identity);
          }
          // 系统选择器的临时源文件用后即清，不长期占用。
          _deletePickerArtifact(outcome);
          await _clearPendingOperation();
          _candidate = _Candidate(path: candidatePath, userId: identity.userId);
          _notify();
          return AvatarCandidateStart.ready(candidatePath);
        } on Object {
          _cleanupQuietly(candidatePath);
          await _clearPendingOperation();
          _deletePickerArtifact(outcome);
          return const AvatarCandidateStart.failed();
        }
    }
  }

  @override
  Future<AvatarCandidateStart> importCandidate({
    required AvatarImportedImage image,
    required AvatarIdentity identity,
  }) async {
    if (!_identityMatches(identity)) {
      return const AvatarCandidateStart.identityChanged();
    }
    if (_picking) return const AvatarCandidateStart.busy();
    _picking = true;
    discardCandidate();
    final int session = ++_pickSession;
    String? candidatePath;
    try {
      const int limit = UiAvatarImageProcessor.maxSourceFileBytes;
      if (image.bytes <= 0 ||
          image.bytes > limit ||
          image.width <= 0 ||
          image.height <= 0 ||
          image.width > UiAvatarImageProcessor.maxSourceDimension ||
          image.height > UiAvatarImageProcessor.maxSourceDimension ||
          image.width * image.height >
              UiAvatarImageProcessor.maxSourcePixelCount) {
        return const AvatarCandidateStart.failed();
      }
      final File source = File(image.path);
      if (await source.length() != image.bytes) {
        return const AvatarCandidateStart.failed();
      }
      if (!_candidateOperationMatches(session, identity)) {
        return _candidateStatusAfterWait(session, identity);
      }
      candidatePath = await _storage.newCandidateFilePath();
      if (!_candidateOperationMatches(session, identity)) {
        return _candidateStatusAfterWait(session, identity);
      }
      final RandomAccessFile output = await File(candidatePath)
          .open(mode: FileMode.write);
      int copied = 0;
      try {
        await for (final List<int> chunk in source.openRead()) {
          if (!_candidateOperationMatches(session, identity)) {
            return _candidateStatusAfterWait(session, identity);
          }
          copied += chunk.length;
          if (copied > limit || copied > image.bytes) {
            throw const AvatarDecodeException('oversized');
          }
          await output.writeFrom(chunk);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      if (copied != image.bytes) return const AvatarCandidateStart.failed();
      final RandomAccessFile input = await File(candidatePath).open();
      final Uint8List header;
      try {
        header = await input.read(24);
      } finally {
        await input.close();
      }
      const List<int> png = <int>[137, 80, 78, 71, 13, 10, 26, 10];
      if (header.length < 24 ||
          List<int>.generate(8, (i) => header[i]).join(',') != png.join(',')) {
        return const AvatarCandidateStart.failed();
      }
      final ByteData data = ByteData.sublistView(header);
      if (data.getUint32(16) != image.width ||
          data.getUint32(20) != image.height) {
        return const AvatarCandidateStart.failed();
      }
      await _processor.ensureDecodable(
        path: candidatePath,
        maxDimension: UiAvatarImageProcessor.maxSourceDimension,
        maxPixelCount: UiAvatarImageProcessor.maxSourcePixelCount,
        maxFileBytes: limit,
      );
      if (!_candidateOperationMatches(session, identity)) {
        return _candidateStatusAfterWait(session, identity);
      }
      _candidate = _Candidate(path: candidatePath, userId: identity.userId);
      final String accepted = candidatePath;
      candidatePath = null;
      _notify();
      return AvatarCandidateStart.ready(accepted);
    } on Object {
      return _candidateOperationMatches(session, identity)
          ? const AvatarCandidateStart.failed()
          : _candidateStatusAfterWait(session, identity);
    } finally {
      _cleanupQuietly(candidatePath);
      _picking = false;
    }
  }

  @override
  Future<AvatarCommitOutcome> commitCandidate({
    required AvatarIdentity identity,
    required AvatarCropParams params,
  }) => _enqueue(() => _commit(identity, params));

  Future<AvatarCommitOutcome> _commit(
    AvatarIdentity identity,
    AvatarCropParams params,
  ) async {
    if (!_identityMatches(identity)) {
      return AvatarCommitOutcome.identityChanged;
    }
    final _Candidate? candidate = _candidate;
    if (_committing ||
        candidate == null ||
        candidate.userId != identity.userId) {
      return AvatarCommitOutcome.noCandidate;
    }
    _committing = true;
    _writeVersion += 1;
    _notify();
    String? tempPath;
    String? finalPath;
    bool indexWritten = false;
    try {
      final Uint8List bytes = await _processor.renderCrop(
        sourcePath: candidate.path,
        params: params,
      );
      if (!_identityMatches(identity) || _candidate != candidate) {
        return AvatarCommitOutcome.identityChanged;
      }
      tempPath = await _storage.newTempFilePathInAvatarDirectory();
      await _storage.writeBytesAtomically(tempPath, bytes);
      final bool valid = await _processor.validateImage(
        path: tempPath,
        width: 512,
        height: 512,
      );
      if (!valid) {
        await _storage.deleteFile(tempPath);
        _committing = false;
        _notify();
        return AvatarCommitOutcome.decodeFailed;
      }
      if (!_identityMatches(identity) || _candidate != candidate) {
        await _storage.deleteFile(tempPath);
        return AvatarCommitOutcome.identityChanged;
      }
      finalPath = await _storage.avatarFilePath(
        await _storage.newAvatarFileName(identity.userId),
      );
      await File(tempPath).rename(finalPath);
      tempPath = null;
      final String? previousEntry = _index.fileFor(identity.userId);
      final AvatarIndexSnapshot newIndex = _index.copyWith(
        writeVersion: _writeVersion,
        entries: <int, String>{
          ..._index.entries,
          identity.userId: p.basename(finalPath),
        },
      );
      await _storage.writeIndex(newIndex);
      indexWritten = true;
      _index = newIndex;
      // The commit is durable from here on; cleanup failures never roll it
      // back.
      _discardCandidateLocked();
      _cleanupPreviousFile(previousEntry, p.basename(finalPath));
      return AvatarCommitOutcome.committed;
    } on AvatarDecodeException {
      _cleanupQuietly(tempPath);
      return AvatarCommitOutcome.decodeFailed;
    } on Object catch (error) {
      _cleanupQuietly(tempPath);
      if (!indexWritten && finalPath != null) {
        _cleanupQuietly(finalPath);
      }
      _diagnostic?.call('avatar commit failed: ${error.runtimeType}');
      return AvatarCommitOutcome.storageFailed;
    } finally {
      // 身份变化、解码失败、存储失败与成功路径统一在此复位 busy 并通知，
      // 处理中切号/退出不会把仓储永久留在 committing 状态。
      _committing = false;
      _notify();
    }
  }

  @override
  void discardCandidate() {
    // 使在途选图会话失效：页面销毁后迟到的 ready 结果一律丢弃。
    _pickSession += 1;
    unawaited(_clearPendingOperation());
    if (_candidate == null) {
      return;
    }
    _discardCandidateLocked();
    _notify();
  }

  @override
  Future<AvatarGallerySaveOutcome> saveCurrentToGallery({
    required AvatarIdentity identity,
    Future<List<int>?> Function()? defaultAvatarPng,
  }) {
    // Single-flight: the busy flag flips synchronously so a second tap while
    // a save is queued or running is ignored.
    if (_savingToGallery) {
      return Future<AvatarGallerySaveOutcome>.value(
        AvatarGallerySaveOutcome.failure,
      );
    }
    _savingToGallery = true;
    _notify();
    return _enqueue(() => _saveToGallery(identity, defaultAvatarPng));
  }

  Future<AvatarGallerySaveOutcome> _saveToGallery(
    AvatarIdentity identity,
    Future<List<int>?> Function()? defaultAvatarPng,
  ) async {
    if (!_identityMatches(identity)) {
      _savingToGallery = false;
      _notify();
      return AvatarGallerySaveOutcome.failure;
    }
    try {
      final Uint8List? bytes;
      final String? entry = _index.fileFor(identity.userId);
      if (entry != null) {
        bytes = await _storage.readBytes(await _storage.avatarFilePath(entry));
      } else {
        final List<int>? rendered = defaultAvatarPng == null
            ? null
            : await defaultAvatarPng();
        bytes = rendered == null ? null : Uint8List.fromList(rendered);
      }
      if (bytes == null || bytes.isEmpty) {
        return AvatarGallerySaveOutcome.failure;
      }
      // 读取/渲染等待期间账号可能已切换：写入库前再复核一次身份。
      if (!_identityMatches(identity)) {
        return AvatarGallerySaveOutcome.failure;
      }
      return await _galleryGateway.savePng(
        fileName: 'wanandroid_avatar_${_stamp()}.png',
        bytes: bytes,
      );
    } on Object catch (error) {
      return AvatarGallerySaveOutcome.failureWith(error);
    } finally {
      _savingToGallery = false;
      _notify();
    }
  }

  @override
  Future<AvatarCandidateStart> consumeRecoveredOperation({
    required AvatarIdentity? identity,
  }) => _enqueue(() => _consumeRecoveredOperation(identity));

  Future<AvatarCandidateStart> _consumeRecoveredOperation(
    AvatarIdentity? identity,
  ) async {
    final PendingAvatarOperation? pending = await _storage
        .readPendingOperation();
    if (pending == null) {
      await _cleanupCandidateDirectory();
      return const AvatarCandidateStart.cancelled();
    }
    if (identity == null) {
      // No verified session after restore: the pending result cannot be
      // attributed, so drop it without touching the index.
      await _clearPendingOperation();
      await _cleanupCandidateDirectory();
      return const AvatarCandidateStart.cancelled();
    }
    final AuthStateView session = _authRepository.view();
    final bool verified =
        session.authenticated &&
        !session.loading &&
        !session.unverified &&
        session.accountVersionKey != null;
    // After a process restart the operation identity is necessarily new, so
    // attribution is re-established from the persisted pending record plus a
    // verified session for the same userId.
    final bool attributable =
        verified &&
        session.userId == pending.userId &&
        _now().difference(pending.createdAt) <= pendingTtl;
    if (!attributable) {
      // Unprovable ownership: drop everything, never touch the index.
      await _clearPendingOperation();
      await _cleanupCandidateDirectory();
      return const AvatarCandidateStart.cancelled();
    }
    final int recoverySession = ++_pickSession;
    final AvatarPickOutcome lost = await _sourceGateway.retrieveLostData();
    if (lost.status != AvatarPickStatus.ready) {
      await _clearPendingOperation();
      await _cleanupCandidateDirectory();
      return const AvatarCandidateStart.cancelled();
    }
    final String pickedPath = lost.copiedPath!;
    String? candidatePath;
    try {
      if (!_candidateOperationMatches(recoverySession, identity)) {
        await _clearPendingOperation();
        _deletePickerArtifact(lost);
        await _cleanupCandidateDirectory();
        return const AvatarCandidateStart.identityChanged();
      }
      await _processor.ensureDecodable(
        path: pickedPath,
        maxDimension: UiAvatarImageProcessor.maxSourceDimension,
        maxPixelCount: UiAvatarImageProcessor.maxSourcePixelCount,
        maxFileBytes: UiAvatarImageProcessor.maxSourceFileBytes,
      );
      if (!_candidateOperationMatches(recoverySession, identity)) {
        await _clearPendingOperation();
        _deletePickerArtifact(lost);
        await _cleanupCandidateDirectory();
        return const AvatarCandidateStart.identityChanged();
      }
      candidatePath = await _storage.newCandidateFilePath();
      await _normalizationGateway.normalizeToPng(
        sourcePath: pickedPath,
        destinationPath: candidatePath,
        maxDimension: UiAvatarImageProcessor.maxSourceDimension,
        maxPixelCount: UiAvatarImageProcessor.maxSourcePixelCount,
        maxFileBytes: UiAvatarImageProcessor.maxSourceFileBytes,
      );
      await _processor.ensureDecodable(
        path: candidatePath,
        maxDimension: UiAvatarImageProcessor.maxSourceDimension,
        maxPixelCount: UiAvatarImageProcessor.maxSourcePixelCount,
        maxFileBytes: UiAvatarImageProcessor.maxSourceFileBytes,
      );
      if (!_candidateOperationMatches(recoverySession, identity)) {
        await _storage.deleteFile(candidatePath);
        await _clearPendingOperation();
        _deletePickerArtifact(lost);
        await _cleanupCandidateDirectory();
        return const AvatarCandidateStart.identityChanged();
      }
      await _clearPendingOperation();
      _deletePickerArtifact(lost);
      _candidate = _Candidate(path: candidatePath, userId: identity.userId);
      _recoveryReady = true;
      _notify();
      return AvatarCandidateStart.ready(candidatePath);
    } on Object {
      _cleanupQuietly(candidatePath);
      await _clearPendingOperation();
      _deletePickerArtifact(lost);
      await _cleanupCandidateDirectory();
      return const AvatarCandidateStart.cancelled();
    }
  }

  @override
  void markRecoveryConsumed() {
    if (_recoveryReady) {
      _recoveryReady = false;
      _notify();
    }
  }

  // --- internals -----------------------------------------------------------

  bool _identityMatches(AvatarIdentity identity) {
    final AuthStateView session = _authRepository.view();
    return session.authenticated &&
        !session.loading &&
        !session.unverified &&
        !session.expiredNotice &&
        !session.storageNotice &&
        session.userId == identity.userId &&
        session.accountVersionKey == identity.accountVersionKey;
  }

  bool _candidateOperationMatches(int session, AvatarIdentity identity) =>
      session == _pickSession && _identityMatches(identity);

  AvatarCandidateStart _candidateStatusAfterWait(
    int session,
    AvatarIdentity identity,
  ) => session == _pickSession && !_identityMatches(identity)
      ? const AvatarCandidateStart.identityChanged()
      : const AvatarCandidateStart.cancelled();

  Future<void> _clearPendingOperation() async {
    _pendingAtStartup = false;
    try {
      await _writePendingOperation(null);
    } on Object {
      _diagnostic?.call('avatar pending cleanup failed');
    }
  }

  Future<void> _writePendingOperation(PendingAvatarOperation? operation) {
    final Future<void> result = _pendingTail.then(
      (_) => _storage.writePendingOperation(operation),
    );
    _pendingTail = result.catchError((Object _) {});
    return result;
  }

  String _pathFor(String fileName) {
    final String dir = _avatarDirectoryPath ?? '';
    return dir.isEmpty ? fileName : p.join(dir, fileName);
  }

  void _handleSessionChanged() {
    // Identity moved on (logout, account switch, expire): any in-flight
    // candidate for another identity is dropped immediately so no page can
    // commit it afterwards. Files stay on disk per the logout contract.
    final _Candidate? candidate = _candidate;
    if (candidate != null) {
      final AuthStateView session = _authRepository.view();
      final bool stillSameVerified =
          session.authenticated &&
          session.userId == candidate.userId &&
          session.accountVersionKey != null;
      if (!stillSameVerified) {
        _discardCandidateLocked();
      }
    }
    _notify();
  }

  void _discardCandidateLocked() {
    final _Candidate? candidate = _candidate;
    if (candidate == null) {
      return;
    }
    _candidate = null;
    _cleanupQuietly(candidate.path);
  }

  void _deletePickerArtifact(AvatarPickOutcome outcome) {
    if (outcome.status == AvatarPickStatus.ready) {
      _cleanupQuietly(outcome.copiedPath);
    }
  }

  void _cleanupPreviousFile(String? previous, String current) {
    if (previous == null || previous == current) {
      return;
    }
    _cleanupQuietly(_pathFor(previous));
  }

  void _cleanupQuietly(String? path) {
    if (path == null) {
      return;
    }
    // Best effort only; never throws into the caller's flow.
    unawaited(_storage.deleteFile(path).catchError((Object _) {}));
  }

  Future<void> _cleanupOrphans() async {
    try {
      final Set<String> keep = <String>{
        ..._index.entries.values,
        p.basename(await _storage.indexFilePath()),
        p.basename(await _storage.pendingFilePath()),
      };
      for (final String name in await _storage.listAllFileNames()) {
        if (!keep.contains(name)) {
          _cleanupQuietly(_pathFor(name));
        }
      }
      await _cleanupCandidateDirectory();
    } on Object {
      _diagnostic?.call('avatar orphan cleanup failed');
    }
  }

  Future<void> _cleanupCandidateDirectory() async {
    try {
      final Directory dir = Directory(await _storage.candidateDirectory());
      if (!await dir.exists()) {
        return;
      }
      await for (final FileSystemEntity entity in dir.list()) {
        _cleanupQuietly(entity.path);
      }
    } on Object {
      _diagnostic?.call('avatar candidate cleanup failed');
    }
  }

  void _notify() {
    for (final void Function() listener in List.of(_listeners)) {
      listener();
    }
  }

  String _uniqueId() =>
      'avatar_${DateTime.now().microsecondsSinceEpoch}_${_randomHex()}';

  String _stamp() {
    final DateTime time = _now();
    String two(int value) => value.toString().padLeft(2, '0');
    final String ms = time.millisecond.toString().padLeft(3, '0');
    // 毫秒 + 随机后缀：同秒多次保存也不会互相覆盖（需求 §3.7）。
    return '${time.year}${two(time.month)}${two(time.day)}_'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}_$ms'
        '_${_randomHex()}';
  }
}

class _Candidate {
  const _Candidate({required this.path, required this.userId});

  final String path;
  final int userId;
}

String _randomHex() =>
    DateTime.now().microsecondsSinceEpoch.remainder(0xFFFFFF).toRadixString(16);
