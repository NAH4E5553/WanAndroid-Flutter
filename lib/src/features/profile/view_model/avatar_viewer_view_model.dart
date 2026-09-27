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

  @override
  AvatarViewerState build() {
    _active = true;
    _repository = ref.read(avatarRepositoryProvider);
    _authRepository = ref.read(authRepositoryProvider);
    _repository.addListener(_publish);
    _authRepository.addListener(_publish);
    ref.onDispose(() {
      _active = false;
      _repository.removeListener(_publish);
      _authRepository.removeListener(_publish);
      // The viewer owns the external picker round-trip. Leaving the route
      // invalidates that operation even when no candidate has been published
      // yet, so a late system result cannot open the adjust page afterwards.
      _repository.discardCandidate();
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
    state = _state();
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
