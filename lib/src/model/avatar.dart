/// Local avatar domain contracts shared across layers. Pure Dart: no Flutter,
/// no `dart:ui`, no platform plugin types.
library;

/// Where an avatar candidate comes from.
enum AvatarSource { camera, gallery }

/// User-applied crop transform captured by the adjust screen.
///
/// Semantics shared with `AvatarImageProcessor` so the final render is
/// deterministic:
/// - `scale` is relative to the base scale where the decoded image fully
///   covers the axis-aligned square crop window (cover fit).
/// - `offsetX`/`offsetY` are the image center offset from the crop center,
///   as a fraction of the crop window side (positive = right/down).
/// - `rotationRadians` is the extra free rotation applied around the image
///   center.
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

/// Single in-flight external avatar operation, persisted before the system
/// camera/gallery opens so an Android process kill can re-attribute the late
/// result.
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

/// Outcome of handing the current avatar bytes to the system gallery.
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

  /// Diagnostic detail kept out of user-facing copy.
  final Object? error;
}

/// Result of the system picker round trip.
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

  /// Candidate copy inside the app temp directory; only for [ready].
  final String? copiedPath;
}

/// UI-facing avatar state for the current session identity, so views never
/// touch file storage, pickers or the processor.
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

  /// A verified session with an operation identity; gates the whole editor
  /// flow (guest/verifying/unverified/expired are all read-only).
  final bool editable;

  /// The current user has a persisted custom avatar file.
  final bool customAvailable;

  /// Absolute path of the persisted avatar file; only when [customAvailable].
  final String? customAvatarPath;

  /// A picked/captured candidate awaits the adjust screen.
  final bool candidateReady;

  /// Absolute path of the candidate copy; only when [candidateReady].
  final String? candidatePath;

  final bool committing;
  final bool savingToGallery;

  /// A process-recovered candidate passed attribution and waits for the app
  /// to navigate to the adjust page; cleared via
  /// `AvatarRepository.markRecoveryConsumed`.
  final bool recoveryReady;
}

/// A direction-normalized PNG copy supplied by the portable picker.
/// The caller owns and releases the external file; the repository only copies it.
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
