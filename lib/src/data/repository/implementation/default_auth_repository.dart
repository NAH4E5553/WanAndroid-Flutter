import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/mapper/wan_response_mapper.dart';
import 'package:wanandroid_flutter/src/data/network/auth_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_commit_coordinator.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_models.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_store.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/model/user.dart';

/// Login diagnostics. Compliant with the logging rules: never logs
/// passwords, cookie values or full request bodies — only envelope codes,
/// messages and counts.
void _logLogin(String message) {
  // ignore: avoid_print
  print('[auth] $message');
}

final class DefaultAuthRepository implements AuthRepository {
  DefaultAuthRepository({
    required SessionStore sessionStore,
    required this._source,
    required this._coordinator,
  }) : _sessions = sessionStore;

  final SessionStore _sessions;
  final AuthNetworkDataSource _source;
  final SessionCommitCoordinator _coordinator;

  User? get currentUser => _sessions.snapshot.user;

  @override
  AuthStateView view() {
    final SessionSnapshot snapshot = _sessions.snapshot;
    return AuthStateView(
      loading:
          snapshot.phase == SessionPhase.loading ||
          snapshot.phase == SessionPhase.verifying,
      authenticated: snapshot.authenticated,
      unverified: snapshot.phase == SessionPhase.unverified,
      expiredNotice:
          snapshot.notice == SessionNotice.expired && !snapshot.authenticated,
      storageNotice: snapshot.notice == SessionNotice.storageError,
      displayName: snapshot.user?.displayName,
    );
  }

  @override
  void addListener(void Function() listener) => _sessions.addListener(listener);

  @override
  void removeListener(void Function() listener) =>
      _sessions.removeListener(listener);

  @override
  Future<DataResult<void>> restore() => _coordinator.run(() async {
    final SessionSnapshot state = await _sessions.initialize();
    if (state.phase != SessionPhase.verifying &&
        state.phase != SessionPhase.unverified) {
      return const DataSuccess<void>(null);
    }
    final SessionRequest request = _sessions.capture();
    final DataResult<UserEnvelope> result = await requestWithData<UserEnvelope>(
      request: () => _source.userInfo(request),
      decode: parseUserInfo,
      cancellation: const LiveRequestCancellation(),
    );
    if (result is DataSuccess<UserEnvelope>) {
      final UserEnvelope envelope = result.value;
      final User user = User(
        id: envelope.id,
        username: envelope.username,
        nickname: envelope.nickname,
      );
      if (await _sessions.verified(request, user)) {
        return const DataSuccess<void>(null);
      }
      return const DataFailure<void>(DataError.sessionChanged);
    }
    final DataError error = (result as DataFailure<UserEnvelope>).error;
    if (error == DataError.sessionExpired) {
      await _sessions.expire(request);
    } else {
      _sessions.verificationFailed(request);
    }
    return DataFailure<void>(error);
  });

  @override
  Future<DataResult<void>> login(
    String username,
    String password,
  ) => _coordinator.run(() async {
    final String trimmed = username.trim();
    if (trimmed.isEmpty ||
        trimmed.length > 200 ||
        password.isEmpty ||
        password.length > 200) {
      return const DataFailure<void>(DataError.invalidResponse);
    }
    SessionRequest? request;
    try {
      _logLogin(
        'login begin (phone=${trimmed.length > 3 ? "***${trimmed.substring(trimmed.length - 4)}" : "***"})',
      );
      request = await _sessions.beginLogin();
      final DataResult<UserEnvelope> result =
          await requestWithData<UserEnvelope>(
            request: () => _source.login(trimmed, password, request),
            decode: (Object? data) {
              if (data is! Map) {
                throw const FormatException();
              }
              return parseUserEnvelope(data);
            },
            cancellation: const LiveRequestCancellation(),
          );
      if (result is! DataSuccess<UserEnvelope>) {
        final DataError error = (result as DataFailure<UserEnvelope>).error;
        _sessions.abortLogin(request);
        return DataFailure<void>(error);
      }
      final UserEnvelope envelope = result.value;
      final User user = User(
        id: envelope.id,
        username: envelope.username,
        nickname: envelope.nickname,
      );
      final bool committed = await _sessions.commitLogin(request, user);
      // Counts only, never cookie values.
      _logLogin('login commit=$committed');
      if (committed) {
        return const DataSuccess<void>(null);
      }
      _sessions.abortLogin(request);
      return const DataFailure<void>(DataError.sessionChanged);
    } on SessionStorageException {
      _logLogin('login aborted: session storage failure');
      return const DataFailure<void>(DataError.storage);
    } on SessionChangedException {
      final SessionRequest? aborted = request;
      if (aborted != null) {
        _sessions.abortLogin(aborted);
      }
      return const DataFailure<void>(DataError.sessionChanged);
    } on Object {
      final SessionRequest? aborted = request;
      if (aborted != null) {
        _sessions.abortLogin(aborted);
      }
      return const DataFailure<void>(DataError.invalidResponse);
    }
  });

  @override
  Future<LogoutOutcome> logout() => _coordinator.run(() async {
    final SessionRequest detached;
    try {
      detached = await _sessions.detach();
    } on SessionStorageException {
      return LogoutOutcome(
        generation: null,
        remote: const DataFailure<void>(DataError.storage),
      );
    }
    // Best-effort: carries only the detached account's cookies, never retries.
    final DataResult<void> remote = await requestWithoutData(
      request: () => _source.logout(detached),
      cancellation: const LiveRequestCancellation(),
    );
    return LogoutOutcome(generation: detached.generation, remote: remote);
  });
}
