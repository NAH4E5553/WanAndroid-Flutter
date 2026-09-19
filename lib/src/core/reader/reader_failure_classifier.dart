import 'package:wanandroid_flutter/src/core/reader/reader_url_policy.dart';

enum ReaderFailureKind { network, http, tls, renderer, timeout }

enum ReaderFailureDisposition { fullPage, diagnostic }

class ReaderFailureClassifier {
  const ReaderFailureClassifier._();

  static ReaderFailureDisposition resource({
    required Uri? activeMainUrl,
    required Uri? callbackUrl,
    required bool? isForMainFrame,
    required ReaderFailureKind kind,
  }) {
    if (kind == ReaderFailureKind.renderer) {
      return ReaderFailureDisposition.fullPage;
    }
    if (isForMainFrame != true ||
        activeMainUrl == null ||
        callbackUrl == null ||
        !ReaderUrlPolicy.samePage(activeMainUrl, callbackUrl)) {
      return ReaderFailureDisposition.diagnostic;
    }
    return ReaderFailureDisposition.fullPage;
  }

  static ReaderFailureDisposition http({
    required Uri? activeMainUrl,
    required Uri? requestUrl,
  }) {
    if (activeMainUrl == null ||
        requestUrl == null ||
        !ReaderUrlPolicy.samePage(activeMainUrl, requestUrl)) {
      return ReaderFailureDisposition.diagnostic;
    }
    return ReaderFailureDisposition.fullPage;
  }
}
