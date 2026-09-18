enum ReaderLoadPhase { idle, loading, loaded, failed, timedOut }

final class ReaderLoadSnapshot {
  const ReaderLoadSnapshot({
    required this.browserInstanceId,
    required this.url,
    required this.phase,
    required this.acceptedCallbacks,
    required this.ignoredCallbacks,
  });

  const ReaderLoadSnapshot.idle()
    : browserInstanceId = 0,
      url = null,
      phase = ReaderLoadPhase.idle,
      acceptedCallbacks = 0,
      ignoredCallbacks = 0;

  final int browserInstanceId;
  final Uri? url;
  final ReaderLoadPhase phase;
  final int acceptedCallbacks;
  final int ignoredCallbacks;
}

/// Rejects callbacks from replaced WebView/controller instances.
///
/// It deliberately does not claim to distinguish two loads performed by the
/// same controller because NavigationDelegate callbacks carry no request ID.
final class ReaderLoadGuard {
  ReaderLoadSnapshot _snapshot = const ReaderLoadSnapshot.idle();
  int _nextBrowserInstanceId = 0;

  ReaderLoadSnapshot get snapshot => _snapshot;

  int beginWithNewBrowser([Uri? url]) {
    final id = ++_nextBrowserInstanceId;
    _snapshot = ReaderLoadSnapshot(
      browserInstanceId: id,
      url: url,
      phase: ReaderLoadPhase.loading,
      acceptedCallbacks: _snapshot.acceptedCallbacks,
      ignoredCallbacks: _snapshot.ignoredCallbacks,
    );
    return id;
  }

  bool bindInitialUrl(int browserInstanceId, Uri url) {
    if (!_accepts(browserInstanceId) ||
        _snapshot.phase != ReaderLoadPhase.loading ||
        _snapshot.url != null) {
      _ignore();
      return false;
    }
    _snapshot = ReaderLoadSnapshot(
      browserInstanceId: _snapshot.browserInstanceId,
      url: url,
      phase: _snapshot.phase,
      acceptedCallbacks: _snapshot.acceptedCallbacks,
      ignoredCallbacks: _snapshot.ignoredCallbacks,
    );
    return true;
  }

  bool pageFinished(int browserInstanceId, Uri url) {
    if (!_accepts(browserInstanceId) ||
        _snapshot.phase != ReaderLoadPhase.loading ||
        _snapshot.url != url) {
      _ignore();
      return false;
    }
    _update(ReaderLoadPhase.loaded, accepted: true);
    return true;
  }

  bool pageFailed(int browserInstanceId, Uri url) {
    if (!_accepts(browserInstanceId) ||
        _snapshot.phase != ReaderLoadPhase.loading ||
        _snapshot.url != url) {
      _ignore();
      return false;
    }
    _update(ReaderLoadPhase.failed, accepted: true);
    return true;
  }

  bool failCurrent(int browserInstanceId) {
    if (!_accepts(browserInstanceId) ||
        _snapshot.phase != ReaderLoadPhase.loading) {
      _ignore();
      return false;
    }
    _update(ReaderLoadPhase.failed, accepted: true);
    return true;
  }

  bool timeout(int browserInstanceId) {
    if (!_accepts(browserInstanceId) ||
        _snapshot.phase != ReaderLoadPhase.loading) {
      _ignore();
      return false;
    }
    _update(ReaderLoadPhase.timedOut, accepted: true);
    return true;
  }

  bool progress(int browserInstanceId) {
    if (!_accepts(browserInstanceId) ||
        _snapshot.phase != ReaderLoadPhase.loading) {
      _ignore();
      return false;
    }
    _update(_snapshot.phase, accepted: true);
    return true;
  }

  bool _accepts(int browserInstanceId) =>
      browserInstanceId == _snapshot.browserInstanceId;

  void _ignore() => _update(_snapshot.phase, ignored: true);

  void _update(
    ReaderLoadPhase phase, {
    bool accepted = false,
    bool ignored = false,
  }) {
    _snapshot = ReaderLoadSnapshot(
      browserInstanceId: _snapshot.browserInstanceId,
      url: _snapshot.url,
      phase: phase,
      acceptedCallbacks: _snapshot.acceptedCallbacks + (accepted ? 1 : 0),
      ignoredCallbacks: _snapshot.ignoredCallbacks + (ignored ? 1 : 0),
    );
  }
}

enum ReaderBackAction { none, webHistoryBack }

ReaderBackAction decideReaderBack({
  required bool didPop,
  required bool webViewCanGoBack,
}) {
  if (didPop) return ReaderBackAction.none;
  return webViewCanGoBack
      ? ReaderBackAction.webHistoryBack
      : ReaderBackAction.none;
}
