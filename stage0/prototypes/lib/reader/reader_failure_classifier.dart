enum ReaderFailureKind { network, http, tls, renderer, timeout }

enum ReaderFailureDisposition { fullPage, diagnostic }

final class ReaderFailureDecision {
  const ReaderFailureDecision({
    required this.disposition,
    required this.kind,
    required this.reason,
  });

  final ReaderFailureDisposition disposition;
  final ReaderFailureKind kind;
  final String reason;

  bool get isFullPage => disposition == ReaderFailureDisposition.fullPage;
}

final class ReaderFailureClassifier {
  const ReaderFailureClassifier._();

  static ReaderFailureDecision resource({
    required Uri? activeMainUrl,
    required Uri? callbackUrl,
    required bool? isForMainFrame,
    required ReaderFailureKind kind,
  }) {
    if (kind == ReaderFailureKind.renderer) {
      return const ReaderFailureDecision(
        disposition: ReaderFailureDisposition.fullPage,
        kind: ReaderFailureKind.renderer,
        reason: 'renderer-affects-current-webview',
      );
    }
    if (isForMainFrame != true) {
      return ReaderFailureDecision(
        disposition: ReaderFailureDisposition.diagnostic,
        kind: kind,
        reason: isForMainFrame == false
            ? 'confirmed-subresource'
            : 'main-frame-unknown',
      );
    }
    if (activeMainUrl == null || callbackUrl != activeMainUrl) {
      return ReaderFailureDecision(
        disposition: ReaderFailureDisposition.diagnostic,
        kind: kind,
        reason: callbackUrl == null ? 'url-missing' : 'url-mismatch',
      );
    }
    return ReaderFailureDecision(
      disposition: ReaderFailureDisposition.fullPage,
      kind: kind,
      reason: 'confirmed-main-frame',
    );
  }

  static ReaderFailureDecision http({
    required Uri? activeMainUrl,
    required Uri? requestUrl,
  }) {
    if (activeMainUrl != null && requestUrl == activeMainUrl) {
      return const ReaderFailureDecision(
        disposition: ReaderFailureDisposition.fullPage,
        kind: ReaderFailureKind.http,
        reason: 'request-matches-main-frame',
      );
    }
    return ReaderFailureDecision(
      disposition: ReaderFailureDisposition.diagnostic,
      kind: ReaderFailureKind.http,
      reason: requestUrl == null
          ? 'request-url-unavailable'
          : 'request-is-not-main-frame',
    );
  }
}
