/// 跨层共享的本地头像领域契约。纯 Dart:不依赖 Flutter、
/// 不依赖 `dart:ui`,也不依赖平台插件类型。
library;

/// 头像候选图的来源。
enum AvatarSource { camera, gallery }

/// 调整页面捕获的用户施加的裁剪变换。
///
/// 语义与 `AvatarImageProcessor` 共享,使最终渲染结果
/// 是确定的:
/// - `scale` 相对于基准 scale,即解码图像完全
///   覆盖轴对齐方形裁剪窗口(cover fit)时的 scale。
/// - `offsetX`/`offsetY` 是图像中心相对裁剪中心的偏移,
///   以裁剪窗口边长的比例表示(正值 = 向右/向下)。
/// - `rotationRadians` 是绕图像中心施加的
///   额外自由旋转。
final class AvatarCropParams {
  const AvatarCropParams({
    required this.scale,
    required this.rotationRadians,
    required this.offsetX,
    required this.offsetY,
  });

  final double scale;
  final double rotationRadians;
  final double offsetX;
  final double offsetY;
}

enum PendingAvatarOperationStatus { awaitingResult }

/// 单条进行中的外部头像操作,在系统相机/相册打开前持久化,
/// 使 Android 进程被杀后可以对迟到结果
/// 重新进行归属。
final class PendingAvatarOperation {
  const PendingAvatarOperation({
    required this.operationId,
    required this.userId,
    required this.source,
    required this.createdAt,
    this.status = PendingAvatarOperationStatus.awaitingResult,
  });

  final String operationId;
  final int userId;
  final AvatarSource source;
  final DateTime createdAt;
  final PendingAvatarOperationStatus status;

  Map<String, Object?> toJson() => <String, Object?>{
    'operationId': operationId,
    'userId': userId,
    'source': source.name,
    'createdAtMilliseconds': createdAt.millisecondsSinceEpoch,
    'status': status.name,
  };

  static PendingAvatarOperation? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final Object? operationId = json['operationId'];
    final Object? userId = json['userId'];
    final Object? source = json['source'];
    final Object? createdAt = json['createdAtMilliseconds'];
    if (operationId is! String ||
        userId is! int ||
        source is! String ||
        createdAt is! int) {
      return null;
    }
    final AvatarSource? sourceValue = AvatarSource.values.asNameMap()[source];
    if (sourceValue == null) {
      return null;
    }
    return PendingAvatarOperation(
      operationId: operationId,
      userId: userId,
      source: sourceValue,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
    );
  }
}

/// 将当前头像字节交给系统相册的结果。
enum AvatarGallerySaveStatus {
  success,
  permissionDenied,
  permissionPermanentlyDenied,
  insufficientSpace,
  failure,
}

final class AvatarGallerySaveOutcome {
  const AvatarGallerySaveOutcome._(this.status, {this.error});

  /// 按状态构造（测试与少见分支使用；诊断字段仅在 failure 时有值）。
  factory AvatarGallerySaveOutcome.of(AvatarGallerySaveStatus status) {
    switch (status) {
      case AvatarGallerySaveStatus.success:
        return success;
      case AvatarGallerySaveStatus.permissionDenied:
        return permissionDenied;
      case AvatarGallerySaveStatus.permissionPermanentlyDenied:
        return permissionPermanentlyDenied;
      case AvatarGallerySaveStatus.insufficientSpace:
        return insufficientSpace;
      case AvatarGallerySaveStatus.failure:
        return failure;
    }
  }

  static const AvatarGallerySaveOutcome success = AvatarGallerySaveOutcome._(
    AvatarGallerySaveStatus.success,
  );
  static const AvatarGallerySaveOutcome permissionDenied =
      AvatarGallerySaveOutcome._(AvatarGallerySaveStatus.permissionDenied);
  static const AvatarGallerySaveOutcome permissionPermanentlyDenied =
      AvatarGallerySaveOutcome._(
        AvatarGallerySaveStatus.permissionPermanentlyDenied,
      );
  static const AvatarGallerySaveOutcome insufficientSpace =
      AvatarGallerySaveOutcome._(AvatarGallerySaveStatus.insufficientSpace);
  static const AvatarGallerySaveOutcome failure = AvatarGallerySaveOutcome._(
    AvatarGallerySaveStatus.failure,
  );

  static AvatarGallerySaveOutcome failureWith(Object error) =>
      AvatarGallerySaveOutcome._(AvatarGallerySaveStatus.failure, error: error);

  final AvatarGallerySaveStatus status;

  /// 诊断细节,不进入面向用户的文案。
  final Object? error;
}

/// 系统选择器一次往返的结果。
enum AvatarPickStatus { ready, cancelled, unavailable }

final class AvatarPickOutcome {
  const AvatarPickOutcome._(this.status, {this.copiedPath});

  const AvatarPickOutcome.ready(String path)
    : this._(AvatarPickStatus.ready, copiedPath: path);
  static const AvatarPickOutcome cancelled = AvatarPickOutcome._(
    AvatarPickStatus.cancelled,
  );
  static const AvatarPickOutcome unavailable = AvatarPickOutcome._(
    AvatarPickStatus.unavailable,
  );

  final AvatarPickStatus status;

  /// 应用临时目录中的候选副本;仅在 [ready] 时有值。
  final String? copiedPath;
}

/// 面向 UI 的当前会话身份头像状态,使 View 永不接触
/// 文件存储、选择器或处理器。
class AvatarStateView {
  const AvatarStateView({
    required this.userId,
    required this.editable,
    required this.customAvailable,
    required this.customAvatarPath,
    required this.candidateReady,
    required this.candidatePath,
    required this.committing,
    required this.savingToGallery,
    required this.recoveryReady,
  });

  final int? userId;

  /// 具有操作身份的已验证会话;是整个编辑流程的门禁
  /// (guest/verifying/unverified/expired 均为只读)。
  final bool editable;

  /// 当前用户已有已持久化的自定义头像文件。
  final bool customAvailable;

  /// 已持久化头像文件的绝对路径;仅在 [customAvailable] 时有值。
  final String? customAvatarPath;

  /// 已挑选/拍摄的候选图等待进入调整页面。
  final bool candidateReady;

  /// 候选副本的绝对路径;仅在 [candidateReady] 时有值。
  final String? candidatePath;

  final bool committing;
  final bool savingToGallery;

  /// 经进程恢复的候选图已通过归属校验,等待应用
  /// 导航到调整页面;通过
  /// `AvatarRepository.markRecoveryConsumed` 清除。
  final bool recoveryReady;
}

/// 便携选择器提供的已完成方向归一化的 PNG 副本。
/// 调用方拥有并负责释放外部文件;仓储只对其进行复制。
final class AvatarImportedImage {
  const AvatarImportedImage({
    required this.path,
    required this.bytes,
    required this.width,
    required this.height,
  });
  final String path;
  final int bytes;
  final int width;
  final int height;
}
