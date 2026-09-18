import 'dart:async';

import 'reader_failure_classifier.dart';
import 'reader_load_guard.dart';

/// Shared by the real delegate and deterministic injected tests.
/// The counters/target are effect probes, not a production history repository
/// or a collection API. Only a new controller starts a guarded attempt.
final class ReaderProbeCallbacks {
  ReaderProbeCallbacks({
    required this.onChanged,
    this.onEvent,
    this.timeoutDuration = const Duration(seconds: 10),
  });

  final void Function() onChanged;
  final void Function(String)? onEvent;
  final Duration timeoutDuration;
  final ReaderLoadGuard _guard = ReaderLoadGuard();
  final List<String> trace = [];
  Timer? _timer;
  bool _disposed = false;
  int progress = 0;
  int historyProbeWrites = 0;
  int diagnosticFailures = 0;
  Uri? collectionTargetProbe;
  ReaderFailureKind? pageFailureKind;
  String status = 'initializing';
  ReaderLoadSnapshot get snapshot => _guard.snapshot;

  int begin(Uri expectedCallbackUrl) {
    if (_disposed) throw StateError('Disposed probe');
    _timer?.cancel();
    final id = _guard.beginWithNewBrowser(expectedCallbackUrl);
    progress = 0;
    collectionTargetProbe = null;
    pageFailureKind = null;
    status = 'browser=$id loading';
    _timer = Timer(timeoutDuration, () {
      if (_disposed || !_guard.timeout(id)) return;
      status = 'browser=$id timedOut';
      _record('timer', id, 'timeout', true);
    });
    return id;
  }

  int beginWithPlatformUrl() {
    if (_disposed) throw StateError('Disposed probe');
    _timer?.cancel();
    final id = _guard.beginWithNewBrowser();
    progress = 0;
    collectionTargetProbe = null;
    pageFailureKind = null;
    status = 'browser=$id loading';
    _timer = Timer(timeoutDuration, () {
      if (_disposed || !_guard.timeout(id)) return;
      status = 'browser=$id timedOut';
      _record('timer', id, 'timeout', true);
    });
    return id;
  }

  void pageStarted(int id, String url, {required String source}) {
    if (_disposed) return;
    final parsed = Uri.tryParse(url);
    if (parsed != null && snapshot.url == null) {
      _guard.bindInitialUrl(id, parsed);
    }
    final accepted = parsed == snapshot.url && _guard.progress(id);
    _record(source, id, 'started:$url', accepted);
  }

  void onProgress(int id, int value, {required String source}) {
    if (_disposed) return;
    final accepted = _guard.progress(id);
    if (accepted) progress = value;
    _record(source, id, 'progress:$value', accepted);
  }

  Future<void> pageFinished(
    int id,
    String url,
    Future<bool> Function() canGoBack, {
    required String source,
  }) async {
    if (_disposed) return;
    final parsed = Uri.tryParse(url);
    final accepted = parsed != null && _guard.pageFinished(id, parsed);
    _record(source, id, 'finished:$url', accepted);
    if (!accepted) return;
    _timer?.cancel();
    status = 'browser=$id finished:$url history=pending';
    onChanged();
    bool history;
    try {
      history = await canGoBack();
    } on Object {
      if (!_disposed && id == snapshot.browserInstanceId) {
        status = 'browser=$id finished:$url history=unavailable';
        onChanged();
      }
      return;
    }
    // A replacement/disposal may have happened during the platform await.
    if (_disposed || id != snapshot.browserInstanceId) return;
    historyProbeWrites++;
    collectionTargetProbe = parsed;
    status = 'browser=$id finished:$url history=$history';
    onChanged();
  }

  void pageFailed(
    int id,
    String? url, {
    required bool? isMainFrame,
    required String source,
    ReaderFailureKind kind = ReaderFailureKind.network,
  }) {
    if (_disposed) return;
    final parsed = url == null ? null : Uri.tryParse(url);
    final decision = ReaderFailureClassifier.resource(
      activeMainUrl: snapshot.url,
      callbackUrl: parsed,
      isForMainFrame: isMainFrame,
      kind: kind,
    );
    final accepted =
        decision.isFullPage &&
        (kind == ReaderFailureKind.renderer
            ? _guard.failCurrent(id)
            : parsed != null && _guard.pageFailed(id, parsed));
    if (accepted) {
      _timer?.cancel();
      collectionTargetProbe = null;
      pageFailureKind = kind;
      status = 'browser=$id failed:${kind.name}';
    } else if (id == snapshot.browserInstanceId) {
      diagnosticFailures++;
    }
    _record(
      source,
      id,
      'error:$url main=$isMainFrame kind=${kind.name} reason=${decision.reason}',
      accepted,
    );
  }

  void httpFailed(
    int id, {
    required Uri? requestUrl,
    required int statusCode,
    required String source,
  }) {
    if (_disposed) return;
    final decision = ReaderFailureClassifier.http(
      activeMainUrl: snapshot.url,
      requestUrl: requestUrl,
    );
    final accepted =
        decision.isFullPage &&
        requestUrl != null &&
        _guard.pageFailed(id, requestUrl);
    if (accepted) {
      _timer?.cancel();
      collectionTargetProbe = null;
      pageFailureKind = ReaderFailureKind.http;
      status = 'browser=$id failed:http status=$statusCode';
    } else if (id == snapshot.browserInstanceId) {
      diagnosticFailures++;
    }
    _record(
      source,
      id,
      'http:$statusCode url=$requestUrl reason=${decision.reason}',
      accepted,
    );
  }

  void _record(String source, int id, String event, bool accepted) {
    trace.add('$source browser=$id $event accepted=$accepted');
    onEvent?.call(trace.last);
    if (trace.length > 32) trace.removeAt(0);
    onChanged();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
