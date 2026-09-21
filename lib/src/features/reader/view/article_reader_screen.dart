import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wanandroid_flutter/src/core/reader/reader_failure_classifier.dart';
import 'package:wanandroid_flutter/src/core/reader/reader_url_policy.dart';
import 'package:wanandroid_flutter/src/core/reader/reading_history_provider.dart';
import 'package:wanandroid_flutter/src/core/ui/app_scaffold.dart';
import 'package:wanandroid_flutter/src/core/ui/app_top_bar.dart';
import 'package:wanandroid_flutter/src/features/reader/navigation/reader_navigation.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ArticleReaderScreen extends ConsumerStatefulWidget {
  const ArticleReaderScreen({
    required this.articleId,
    required this.title,
    required this.url,
    required this.onExit,
    required this.onPopped,
    this.allowLoopbackFixture = false,
    this.loadTimeout = const Duration(seconds: 30),
    this.onControllerReady,
    this.collectState,
    this.onToggleCollect,
    this.onLogin,
    super.key,
  });

  final int? articleId;
  final String title;
  final String url;
  final VoidCallback onExit;
  final VoidCallback onPopped;
  final bool allowLoopbackFixture;
  final Duration loadTimeout;
  final ValueChanged<WebViewController>? onControllerReady;

  /// Session/collection wiring injected from the app layer; null in isolated
  /// fixtures keeps the stage-4 placeholder behaviour.
  final CollectMenuState? Function()? collectState;
  final void Function(CollectionCollectIntent intent)? onToggleCollect;
  final VoidCallback? onLogin;

  @override
  ConsumerState<ArticleReaderScreen> createState() =>
      _ArticleReaderScreenState();
}

class _ArticleReaderScreenState extends ConsumerState<ArticleReaderScreen> {
  WebViewController? _controller;
  Uri? _target;
  Uri? _activeUrl;
  Timer? _timeout;
  int _browserInstance = 0;
  bool _loading = true;
  bool _canGoBack = false;
  bool _failed = false;
  bool _timedOut = false;
  bool _uncertainHttpError = false;
  ReaderFailureKind? _failureKind;
  bool _backBusy = false;

  @override
  void initState() {
    super.initState();
    _target = ReaderUrlPolicy.articleUrl(
      widget.url,
      allowLoopbackFixture: widget.allowLoopbackFixture,
    );
    if (_target != null) {
      unawaited(_replaceBrowser());
    } else {
      final Uri? external = Uri.tryParse(widget.url.trim());
      if (external != null &&
          ReaderUrlPolicy.classify(external) ==
              ReaderUrlAction.confirmExternal) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_confirmExternal(external));
        });
      }
    }
  }

  @override
  void dispose() {
    _browserInstance++;
    _timeout?.cancel();
    super.dispose();
  }

  bool _current(int id) => mounted && id == _browserInstance;

  void _armTimeout(int id) {
    _timeout?.cancel();
    _timeout = Timer(widget.loadTimeout, () {
      if (!_current(id) || !_loading) return;
      setState(() {
        _loading = false;
        _failed = true;
        _timedOut = true;
        _failureKind = ReaderFailureKind.timeout;
      });
    });
  }

  Future<void> _replaceBrowser() async {
    final Uri? target = _target;
    if (target == null) return;
    final int id = ++_browserInstance;
    _timeout?.cancel();
    final WebViewController controller = WebViewController();
    _controller = controller;
    widget.onControllerReady?.call(controller);
    _activeUrl = target;
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
        _timedOut = false;
        _canGoBack = false;
        _uncertainHttpError = false;
        _failureKind = null;
      });
    }
    _armTimeout(id);
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            if (!_current(id)) return NavigationDecision.prevent;
            final Uri? uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (!request.isMainFrame) {
              return ReaderUrlPolicy.classify(
                        uri,
                        allowLoopbackFixture: widget.allowLoopbackFixture,
                      ) ==
                      ReaderUrlAction.inApp
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            }
            switch (ReaderUrlPolicy.classify(
              uri,
              allowLoopbackFixture: widget.allowLoopbackFixture,
            )) {
              case ReaderUrlAction.inApp:
                return NavigationDecision.navigate;
              case ReaderUrlAction.confirmExternal:
                unawaited(_confirmExternal(uri));
                return NavigationDecision.prevent;
              case ReaderUrlAction.block:
                return NavigationDecision.prevent;
            }
          },
          onPageStarted: (String raw) {
            if (!_current(id) || _failed || _timedOut) return;
            final Uri? uri = Uri.tryParse(raw);
            if (uri == null ||
                ReaderUrlPolicy.classify(
                      uri,
                      allowLoopbackFixture: widget.allowLoopbackFixture,
                    ) !=
                    ReaderUrlAction.inApp) {
              return;
            }
            setState(() {
              _activeUrl = uri;
              _loading = true;
              _failed = false;
              _timedOut = false;
              _uncertainHttpError = false;
              _failureKind = null;
            });
            _armTimeout(id);
          },
          onPageFinished: (String raw) {
            if (!_current(id) || !_loading || _failed) return;
            final Uri? uri = Uri.tryParse(raw);
            if (uri == null ||
                _activeUrl == null ||
                !ReaderUrlPolicy.samePage(uri, _activeUrl!)) {
              return;
            }
            _timeout?.cancel();
            setState(() => _loading = false);
            unawaited(_updateBack(id, controller));
            if (!_uncertainHttpError) unawaited(_recordHistory(id, uri));
          },
          onWebResourceError: (WebResourceError error) {
            if (!_current(id)) {
              return;
            }
            final Uri? uri = Uri.tryParse(error.url ?? '');
            final ReaderFailureKind kind = switch (error.errorType) {
              WebResourceErrorType.failedSslHandshake => ReaderFailureKind.tls,
              WebResourceErrorType.webContentProcessTerminated ||
              WebResourceErrorType.webViewInvalidated =>
                ReaderFailureKind.renderer,
              WebResourceErrorType.timeout => ReaderFailureKind.timeout,
              _ => ReaderFailureKind.network,
            };
            // Renderer death can strike long after the page finished loading;
            // it always invalidates the WebView, so it bypasses the loading
            // guard that other error kinds require.
            if (kind == ReaderFailureKind.renderer) {
              if (!_failed) _fail(id, kind);
              return;
            }
            if (!_loading || _failed) {
              return;
            }
            if (ReaderFailureClassifier.resource(
                  activeMainUrl: _activeUrl,
                  callbackUrl: uri,
                  isForMainFrame: error.isForMainFrame,
                  kind: kind,
                ) !=
                ReaderFailureDisposition.fullPage) {
              return;
            }
            _fail(id, kind);
          },
          onHttpError: (HttpResponseError error) {
            if (_current(id) && _loading && error.request?.uri == null) {
              _uncertainHttpError = true;
            }
            if (!_current(id) || !_loading) {
              return;
            }
            if (ReaderFailureClassifier.http(
                  activeMainUrl: _activeUrl,
                  requestUrl: error.request?.uri,
                ) !=
                ReaderFailureDisposition.fullPage) {
              return;
            }
            _fail(id, ReaderFailureKind.http);
          },
        ),
      );
      if (!_current(id)) return;
      await controller.loadRequest(target);
    } on Object {
      _fail(id, ReaderFailureKind.network);
    }
  }

  void _fail(int id, ReaderFailureKind kind) {
    if (!_current(id) || _failed) return;
    _timeout?.cancel();
    setState(() {
      _loading = false;
      _failed = true;
      _canGoBack = false;
      _failureKind = kind;
    });
  }

  Future<void> _recordHistory(int id, Uri uri) async {
    if (!_current(id) || _failed) return;
    try {
      await ref
          .read(readingHistoryRepositoryProvider)
          .record(
            url: uri.toString(),
            title: widget.title,
            articleId:
                _target != null && ReaderUrlPolicy.samePage(uri, _target!)
                ? widget.articleId
                : null,
          );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('阅读历史保存失败')));
      }
    }
  }

  Future<void> _updateBack(int id, WebViewController controller) async {
    try {
      final bool canGoBack = await controller.canGoBack();
      if (_current(id) && !_failed) setState(() => _canGoBack = canGoBack);
    } on Object {
      // Keep the last known value; an unavailable platform observation is not false.
    }
  }

  Future<void> _back() async {
    if (_backBusy) return;
    final WebViewController? controller = _controller;
    if (_canGoBack && controller != null) {
      _backBusy = true;
      try {
        await controller.goBack();
        await _updateBack(_browserInstance, controller);
      } on Object {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('网页返回失败，请重试')));
        }
      } finally {
        _backBusy = false;
      }
    } else {
      widget.onExit();
    }
  }

  Future<void> _toggleCollect() async {
    final CollectMenuState? state = widget.collectState?.call();
    if (state == null || !state.authenticated || state.busy) {
      return;
    }
    final int? generation = state.generation;
    if (generation == null) {
      return;
    }
    widget.onToggleCollect?.call(
      CollectionCollectIntent(
        articleId: widget.articleId,
        collected: state.collected,
        generation: generation,
      ),
    );
  }

  Future<void> _confirmExternal(Uri uri) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('打开外部链接？'),
        content: Text(uri.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('打开'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
            mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('无法打开外部链接')));
        }
      } on Object {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('无法打开外部链接')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_canGoBack,
    onPopInvokedWithResult: (bool didPop, void result) {
      if (didPop) {
        widget.onPopped();
      } else if (_canGoBack) {
        unawaited(_back());
      }
    },
    child: AppScaffold(
      topBar: AppTopBar(
        title: widget.title,
        onBack: () => unawaited(_back()),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_vert),
            onSelected: (String action) async {
              if (action == 'refresh') {
                await _controller?.reload();
              } else if (action == 'external' && _activeUrl != null) {
                await _confirmExternal(_activeUrl!);
              } else if (action == 'collect' && mounted) {
                final CollectMenuState? state = widget.collectState?.call();
                if (state == null || !state.authenticated) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('登录后才能收藏')));
                  widget.onLogin?.call();
                } else if (!state.busy) {
                  unawaited(_toggleCollect());
                }
              }
            },
            itemBuilder: (_) {
              final CollectMenuState? state = widget.collectState?.call();
              final bool collectable = state != null && state.authenticated;
              final String collectLabel = state?.collected ?? false
                  ? '取消收藏'
                  : '收藏';
              return <PopupMenuItem<String>>[
                const PopupMenuItem<String>(
                  value: 'refresh',
                  child: Text('刷新'),
                ),
                const PopupMenuItem<String>(
                  value: 'external',
                  child: Text('浏览器打开'),
                ),
                PopupMenuItem<String>(
                  value: 'collect',
                  enabled: !collectable || !(state.busy),
                  child: Text(collectLabel),
                ),
              ];
            },
          ),
        ],
      ),
      body: _target == null
          ? const Center(child: Text('链接无效或不受支持'))
          : Stack(
              children: [
                if (_controller != null && !_failed)
                  WebViewWidget(
                    key: ValueKey<int>(_browserInstance),
                    controller: _controller!,
                  ),
                if (_loading) const LinearProgressIndicator(),
                if (_failed)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(switch (_failureKind) {
                          ReaderFailureKind.timeout => '加载超时',
                          ReaderFailureKind.http => '页面响应异常',
                          ReaderFailureKind.tls => '安全连接失败',
                          ReaderFailureKind.renderer => '网页进程异常',
                          _ => '页面加载失败',
                        }),
                        TextButton(
                          onPressed: _replaceBrowser,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    ),
  );
}
