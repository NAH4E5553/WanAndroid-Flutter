import 'dart:async';

import 'package:album_picker/models.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/avatar_repository.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';

final NotifierProvider<AvatarViewerViewModel, AvatarViewerState>
avatarViewerViewModelProvider =
    NotifierProvider.autoDispose<AvatarViewerViewModel, AvatarViewerState>(
      AvatarViewerViewModel.new,
    );

/// 查看页动作结果（对 Feature 屏蔽仓储契约类型）。
enum AvatarViewerAction {
  adjustReady,
  cancelled,
  unavailable,
  failed,
  identityChanged,
}

class AvatarViewerState {
  const AvatarViewerState({required this.avatar, required this.identity});

  final AvatarStateView avatar;

  /// 当前可编辑会话的操作身份；游客/未验证为 null，此时不提供任何写操作。
  final AvatarIdentity? identity;

  bool get editable => identity != null;
}

/// 查看头像页状态：订阅仓储事实（当前头像、会话身份），不持有第二份状态。
class AvatarViewerViewModel extends Notifier<AvatarViewerState> {
  late final AvatarRepository _repository;
  late final AuthRepository _authRepository;
  bool _active = true;
  AlbumCancellation? _albumCancellation;
  AvatarIdentity? _albumIdentity;

  @override
  AvatarViewerState build() {
    _active = true;
    _repository = ref.read(avatarRepositoryProvider);
    _authRepository = ref.read(authRepositoryProvider);
    _repository.addListener(_publish);
    _authRepository.addListener(_publish);
    ref.onDispose(() {
      _active = false;
      _albumCancellation?.cancel();
      _repository.removeListener(_publish);
      _authRepository.removeListener(_publish);
      // 查看页拥有与外部选图器之间的整轮往返交互。离开路由
      // 会使该操作失效——即使尚未发布任何候选图——因此迟到的
      // 系统结果无法在之后打开调整页。把仓储通知推迟到 Riverpod
      // 完成本生命周期回调之后；
      // 同步通知可能会写入另一个 Provider。
      scheduleMicrotask(_repository.discardCandidate);
    });
    return _state();
  }

  AvatarViewerState _state() {
    final AvatarStateView avatar = _repository.view();
    return AvatarViewerState(avatar: avatar, identity: _identity());
  }

  AvatarIdentity? _identity() {
    final AuthStateView session = _authRepository.view();
    if (session.userId == null || session.accountVersionKey == null) {
      return null;
    }
    return AvatarIdentity(
      userId: session.userId!,
      accountVersionKey: session.accountVersionKey!,
    );
  }

  void _publish() {
    if (!_active) return;
    final AvatarIdentity? current = _identity();
    if (_albumIdentity != null &&
        (current?.userId != _albumIdentity!.userId ||
            current?.accountVersionKey != _albumIdentity!.accountVersionKey)) {
      _albumCancellation?.cancel();
    }
    state = _state();
  }

  Future<AvatarViewerAction> startAlbum(
    Future<AlbumResult> Function(AlbumCancellation cancellation) show,
  ) async {
    if (_albumCancellation != null) return AvatarViewerAction.cancelled;
    final AvatarIdentity? identity = _identity();
    if (identity == null) return AvatarViewerAction.identityChanged;
    final AlbumCancellation cancellation = AlbumCancellation();
    _albumCancellation = cancellation;
    _albumIdentity = identity;
    AlbumFileLease? lease;
    try {
      final AlbumResult result = await show(cancellation);
      lease = result.lease;
      final AvatarIdentity? current = _identity();
      if (!_active ||
          cancellation.cancelled ||
          current?.userId != identity.userId ||
          current?.accountVersionKey != identity.accountVersionKey) {
        return AvatarViewerAction.cancelled;
      }
      switch (result.kind) {
        case AlbumResultKind.cameraRequested:
          return await startCandidate(AvatarSource.camera);
        case AlbumResultKind.systemPickerRequested:
          return await startCandidate(AvatarSource.gallery);
        case AlbumResultKind.cancelled:
          return AvatarViewerAction.cancelled;
        case AlbumResultKind.failed:
          return AvatarViewerAction.failed;
        case AlbumResultKind.selected:
          if (lease == null ||
              lease.contractVersion != 1 ||
              !lease.upright ||
              lease.mime != 'image/png' ||
              lease.metadataPolicy != 'stripped') {
            return AvatarViewerAction.failed;
          }
          final AvatarCandidateStart imported = await _repository
              .importCandidate(
                image: AvatarImportedImage(
                  path: lease.path,
                  bytes: lease.byteLength,
                  width: lease.width,
                  height: lease.height,
                ),
                identity: identity,
              );
          if (!_active || cancellation.cancelled) {
            return AvatarViewerAction.cancelled;
          }
          return imported.status == AvatarCandidateStartStatus.ready
              ? AvatarViewerAction.adjustReady
              : imported.status == AvatarCandidateStartStatus.identityChanged
              ? AvatarViewerAction.identityChanged
              : AvatarViewerAction.failed;
      }
    } on Object {
      return AvatarViewerAction.failed;
    } finally {
      try {
        await lease?.release();
      } on Object {
        /* 包的清理仍保持可重试。 */
      }
      cancellation.cancel();
      _albumCancellation = null;
      _albumIdentity = null;
    }
  }

  /// 拍照或相册选图：仓储打开系统页并在返回后校验身份；ready 时由页面导航
  /// 到调整页。取消/失败/身份变化均保持当前头像。
  Future<AvatarViewerAction> startCandidate(AvatarSource source) async {
    final AvatarIdentity? identity = _identity();
    if (identity == null) {
      return AvatarViewerAction.identityChanged;
    }
    final AvatarCandidateStart result = await _repository.startCandidate(
      source: source,
      identity: identity,
    );
    if (_active) {
      state = _state();
    }
    switch (result.status) {
      case AvatarCandidateStartStatus.ready:
        return AvatarViewerAction.adjustReady;
      case AvatarCandidateStartStatus.cancelled:
        return AvatarViewerAction.cancelled;
      case AvatarCandidateStartStatus.unavailable:
        return AvatarViewerAction.unavailable;
      case AvatarCandidateStartStatus.failed:
        return AvatarViewerAction.failed;
      case AvatarCandidateStartStatus.busy:
        // 并发触发被忽略：无导航、无提示。
        return AvatarViewerAction.cancelled;
      case AvatarCandidateStartStatus.identityChanged:
        return AvatarViewerAction.identityChanged;
    }
  }

  /// 保存查看页当前展示的头像到系统相册。默认头像时由页面渲染当前主题色的
  /// 512×512 透明 PNG。
  Future<AvatarGallerySaveStatus> saveCurrentToGallery({
    required Future<List<int>?> Function() renderDefaultAvatarPng,
  }) async {
    final AvatarIdentity? identity = _identity();
    if (identity == null) {
      return AvatarGallerySaveStatus.failure;
    }
    final AvatarGallerySaveOutcome outcome = await _repository
        .saveCurrentToGallery(
          identity: identity,
          defaultAvatarPng: renderDefaultAvatarPng,
        );
    return outcome.status;
  }
}
