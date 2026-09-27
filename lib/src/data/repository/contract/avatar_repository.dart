import 'package:wanandroid_flutter/src/model/avatar.dart';

export 'package:wanandroid_flutter/src/model/avatar.dart' show AvatarStateView;

/// Operation identity captured from `AuthStateView` before any avatar
/// operation. Pure value object; the repository re-validates it against the
/// current session identity before accepting results or committing.
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

/// Result of opening the system camera/gallery for a new candidate.
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

  /// Candidate copy inside the app temp directory; only for [ready].
  final String? candidatePath;
}

enum AvatarCommitStatus {
  committed,
  identityChanged,
  noCandidate,
  decodeFailed,
  storageFailed,
}

/// Result of the adjust-screen commit. Every non-committed outcome leaves the
/// persisted index and the previously committed avatar untouched.
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

/// Single authority for local avatar facts, keyed by the server-stable
/// `userId`. Views subscribe via the listener pair; pages must never keep a
/// second writable copy of the avatar state.
abstract interface class AvatarRepository {
  void addListener(void Function() listener);

  void removeListener(void Function() listener);

  /// Current avatar state for the session identity the repository observed.
  AvatarStateView view();

  /// Opens the system camera (or gallery picker) for a new candidate.
  ///
  /// Persists the single `PendingAvatarOperation` before the external page
  /// opens, copies the returned image into the app temp directory and
  /// re-validates [identity] when the external page comes back. The caller
  /// still checks its own route validity before navigating to the adjust
  /// page.
  Future<AvatarCandidateStart> startCandidate({
    required AvatarSource source,
    required AvatarIdentity identity,
  });

  /// Runs the decode/transform/crop/encode pipeline for the current
  /// candidate and atomically commits it as the user's avatar. Any failure
  /// keeps the previous avatar and the persisted index unchanged.
  Future<AvatarCommitOutcome> commitCandidate({
    required AvatarIdentity identity,
    required AvatarCropParams params,
  });

  /// Drops the current candidate and deletes its temporary file.
  void discardCandidate();

  /// Hands the currently committed avatar (or the provided default-avatar
  /// rendering) to the system gallery. Single-flight; repeated calls while
  /// busy are ignored and report [AvatarGallerySaveStatus.failure] is never
  /// shown twice - they simply do not start a second write.
  Future<AvatarGallerySaveOutcome> saveCurrentToGallery({
    required AvatarIdentity identity,

    /// Pre-rendered `512×512` transparent PNG of the default avatar badge in
    /// the current theme colors; required when no custom avatar is committed.
    Future<List<int>?> Function()? defaultAvatarPng,
  });

  /// Whether a persisted pending operation survived a process restart and is
  /// still waiting to be resolved.
  bool hasPendingOperation();

  /// Clears the recovery flag after the app handled (navigated to) a
  /// recovered candidate.
  void markRecoveryConsumed();

  /// Called once after the session restore finished. Validates the persisted
  /// pending operation against [identity] and the lost picker data; when the
  /// result is attributable (same verified `userId`, unique pending record,
  /// younger than 24 hours, file exists and decodes) the candidate is
  /// prepared for the adjust page. Otherwise all temporary artifacts are
  /// dropped.
  Future<AvatarCandidateStart> consumeRecoveredOperation({
    required AvatarIdentity? identity,
  });
}
