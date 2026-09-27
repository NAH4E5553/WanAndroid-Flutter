import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/avatar_repository.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';

final NotifierProvider<AvatarAdjustViewModel, AvatarAdjustState>
avatarAdjustViewModelProvider =
    NotifierProvider.autoDispose<AvatarAdjustViewModel, AvatarAdjustState>(
      AvatarAdjustViewModel.new,
    );

/// 调整页动作结果（对 Feature 屏蔽仓储契约类型）。
enum AvatarAdjustCommit {
  committed,
  identityChanged,
  noCandidate,
  decodeFailed,
  storageFailed,
}

class AvatarAdjustState {
  const AvatarAdjustState({
    required this.candidateReady,
    required this.candidatePath,
    required this.committing,
  });

  final bool candidateReady;
  final String? candidatePath;
  final bool committing;

  /// 无候选（进入即没有可调整图片）：页面应立即退出。
  bool get missing => !candidateReady && !committing;
}

/// 调整页状态：候选图片来自仓储；页面离开（dispose）即丢弃候选。
class AvatarAdjustViewModel extends Notifier<AvatarAdjustState> {
  late final AvatarRepository _repository;
  late final AuthRepository _authRepository;
  bool _active = true;

  @override
  AvatarAdjustState build() {
    _active = true;
    _repository = ref.read(avatarRepositoryProvider);
    _authRepository = ref.read(authRepositoryProvider);
    _repository.addListener(_publish);
    ref.onDispose(() {
      _active = false;
      _repository.removeListener(_publish);
      // 取消语义：离开调整页即丢弃候选，当前头像不变。
      // Riverpod 禁止在 provider 生命周期回调内同步触发其他 provider
      // 的状态写入；仓储通知延后到本轮销毁完成后再发送。
      scheduleMicrotask(_repository.discardCandidate);
    });
    return _state();
  }

  AvatarAdjustState _state() {
    final AvatarStateView avatar = _repository.view();
    return AvatarAdjustState(
      candidateReady: avatar.candidateReady,
      candidatePath: avatar.candidatePath,
      committing: avatar.committing,
    );
  }

  void _publish() {
    if (!_active) return;
    state = _state();
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

  /// 提交当前候选：解码/重绘/裁切/编码/原子保存；任何失败保持旧头像。
  Future<AvatarAdjustCommit> commit(AvatarCropParams params) async {
    final AvatarIdentity? identity = _identity();
    if (identity == null) {
      return AvatarAdjustCommit.identityChanged;
    }
    final AvatarCommitOutcome outcome = await _repository.commitCandidate(
      identity: identity,
      params: params,
    );
    if (_active) {
      state = _state();
    }
    switch (outcome.status) {
      case AvatarCommitStatus.committed:
        return AvatarAdjustCommit.committed;
      case AvatarCommitStatus.identityChanged:
        return AvatarAdjustCommit.identityChanged;
      case AvatarCommitStatus.noCandidate:
        return AvatarAdjustCommit.noCandidate;
      case AvatarCommitStatus.decodeFailed:
        return AvatarAdjustCommit.decodeFailed;
      case AvatarCommitStatus.storageFailed:
        return AvatarAdjustCommit.storageFailed;
    }
  }
}
