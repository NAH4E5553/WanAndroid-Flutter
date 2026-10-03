import 'package:wanandroid_flutter/src/model/avatar.dart';

export 'package:wanandroid_flutter/src/model/avatar.dart' show AvatarStateView;

/// 在任何头像操作开始前从 `AuthStateView` 捕获的操作身份。纯值对象;
/// 在接纳结果或提交之前,仓储都会将其与当前的
/// 会话身份重新校验。
final class AvatarIdentity {
  const AvatarIdentity({required this.userId, required this.accountVersionKey});

  final int userId;
  final String accountVersionKey;
}

enum AvatarCandidateStartStatus {
  ready,
  cancelled,
  unavailable,
  identityChanged,
  failed,
  busy,
}

/// 为新候选打开系统相机/相册的结果。
final class AvatarCandidateStart {
  const AvatarCandidateStart._(this.status, {this.candidatePath});

  const AvatarCandidateStart.ready(String path)
    : this._(AvatarCandidateStartStatus.ready, candidatePath: path);
  const AvatarCandidateStart.cancelled()
    : this._(AvatarCandidateStartStatus.cancelled);
  const AvatarCandidateStart.unavailable()
    : this._(AvatarCandidateStartStatus.unavailable);
  const AvatarCandidateStart.identityChanged()
    : this._(AvatarCandidateStartStatus.identityChanged);
  const AvatarCandidateStart.failed()
    : this._(AvatarCandidateStartStatus.failed);
  const AvatarCandidateStart.busy() : this._(AvatarCandidateStartStatus.busy);

  final AvatarCandidateStartStatus status;

  /// 位于应用临时目录中的候选副本;仅在 [ready] 时存在。
  final String? candidatePath;
}

enum AvatarCommitStatus {
  committed,
  identityChanged,
  noCandidate,
  decodeFailed,
  storageFailed,
}

/// 调整页提交的结果。任何非 committed 的结局都保持已持久化的索引
/// 和先前已提交的头像不被改动。
final class AvatarCommitOutcome {
  const AvatarCommitOutcome._(this.status);

  final AvatarCommitStatus status;

  static const AvatarCommitOutcome committed = AvatarCommitOutcome._(
    AvatarCommitStatus.committed,
  );
  static const AvatarCommitOutcome identityChanged = AvatarCommitOutcome._(
    AvatarCommitStatus.identityChanged,
  );
  static const AvatarCommitOutcome noCandidate = AvatarCommitOutcome._(
    AvatarCommitStatus.noCandidate,
  );
  static const AvatarCommitOutcome decodeFailed = AvatarCommitOutcome._(
    AvatarCommitStatus.decodeFailed,
  );
  static const AvatarCommitOutcome storageFailed = AvatarCommitOutcome._(
    AvatarCommitStatus.storageFailed,
  );
}

/// 本地头像事实的唯一权威,以服务端稳定的 `userId` 为键。
/// View 通过 listener 对订阅;页面绝不得保留
/// 第二份可写的头像状态副本。
abstract interface class AvatarRepository {
  void addListener(void Function() listener);

  void removeListener(void Function() listener);

  /// 仓储当前观察到的会话身份所对应的头像状态。
  AvatarStateView view();

  /// 为新候选打开系统相机(或相册选择器)。
  ///
  /// 在外部页面打开之前,先持久化这条唯一的 `PendingAvatarOperation`,
  /// 把返回的图片复制到应用临时目录,
  /// 并在外部页面返回时重新校验 [identity]。
  /// 调用方在跳转到调整页之前,仍须自行检查其自身路由的
  /// 有效性。
  Future<AvatarCandidateStart> startCandidate({
    required AvatarSource source,
    required AvatarIdentity identity,
  });

  /// 导入一幅已经摆正、且已剥离元数据的 PNG,不做第二次 EXIF 变换。
  /// 不创建外部选择器的 pending/lost-data 记录。
  Future<AvatarCandidateStart> importCandidate({
    required AvatarImportedImage image,
    required AvatarIdentity identity,
  });

  /// 对当前候选执行 decode/transform/crop/encode 流水线,并以原子方式
  /// 将其提交为用户头像。任何失败都保持先前头像和已持久化的索引
  /// 不变。
  Future<AvatarCommitOutcome> commitCandidate({
    required AvatarIdentity identity,
    required AvatarCropParams params,
  });

  /// 丢弃当前候选并删除其临时文件。
  void discardCandidate();

  /// 把当前已提交的头像(或所提供的默认头像渲染图)交给系统相册。
  /// 单飞;busy 期间的重复调用会被忽略,且 [AvatarGallerySaveStatus.failure]
  /// 失败报告绝不会出现两次——
  /// 它们只是不会启动第二次写入。
  Future<AvatarGallerySaveOutcome> saveCurrentToGallery({
    required AvatarIdentity identity,

    /// 以当前主题颜色预渲染的 `512×512` 默认头像徽标透明 PNG;
    /// 尚未提交自定义头像时必填。
    Future<List<int>?> Function()? defaultAvatarPng,
  });

  /// 已持久化的 pending 操作是否在进程重启后存活,
  /// 且至今仍在等待处理。
  bool hasPendingOperation();

  /// 在应用处理完(导航到)某个恢复出的候选之后,
  /// 清除恢复标记。
  void markRecoveryConsumed();

  /// 在会话恢复完成后调用一次。针对 [identity] 与丢失的选择器数据,校验
  /// 已持久化的 pending 操作;当结果可归属时(同一已验证 `userId`、唯一的
  /// pending 记录、未超过 24 小时、且文件存在并可解码),
  /// 该候选会被准备就绪,
  /// 以供调整页使用。
  /// 否则,所有临时产物一律被丢弃。
  Future<AvatarCandidateStart> consumeRecoveredOperation({
    required AvatarIdentity? identity,
  });
}
