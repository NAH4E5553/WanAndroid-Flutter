import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'reader/reader_failure_classifier.dart';
import 'reader/reader_load_guard.dart';
import 'reader/reader_probe_callbacks.dart';

void main() => runApp(const WebViewPrototypeApp());

class WebViewPrototypeApp extends StatelessWidget {
  const WebViewPrototypeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewProbe(),
    );
  }
}

final class ReaderResourceProbe extends ChangeNotifier {
  int mountedReaders = 0;
  int disposedReaders = 0;
  int webHistoryBacks = 0;
  final List<String> lifecycleEvents = [];

  void readerMounted() {
    mountedReaders++;
    scheduleMicrotask(notifyListeners);
  }

  void readerDisposed() {
    disposedReaders++;
    scheduleMicrotask(notifyListeners);
  }

  void webHistoryBack() {
    webHistoryBacks++;
    notifyListeners();
  }

  void lifecycleChanged(AppLifecycleState state) {
    lifecycleEvents.add(state.name);
    if (lifecycleEvents.length > 8) lifecycleEvents.removeAt(0);
    notifyListeners();
  }

  String get summary =>
      'mounted=$mountedReaders disposed=$disposedReaders '
      'webBacks=$webHistoryBacks lifecycle=${lifecycleEvents.join(",")}';
}

class ReaderBackPrototypeApp extends StatefulWidget {
  const ReaderBackPrototypeApp({super.key});

  @override
  State<ReaderBackPrototypeApp> createState() => _ReaderBackPrototypeAppState();
}

class _ReaderBackPrototypeAppState extends State<ReaderBackPrototypeApp> {
  final ReaderResourceProbe _resourceProbe = ReaderResourceProbe();

  @override
  void dispose() {
    _resourceProbe.dispose();
    super.dispose();
  }

  void _openReader(BuildContext context) {
    Widget builder(BuildContext context) =>
        WebViewProbe(routeBackEnabled: true, resourceProbe: _resourceProbe);
    final route = Theme.of(context).platform == TargetPlatform.iOS
        ? CupertinoPageRoute<void>(builder: builder)
        : MaterialPageRoute<void>(builder: builder);
    Navigator.of(context).push(route);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (navigatorContext) => Scaffold(
          appBar: AppBar(title: const Text('Reader Back Stage 0')),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListenableBuilder(
                  listenable: _resourceProbe,
                  builder: (context, child) => Text(
                    _resourceProbe.summary,
                    key: const Key('resource-diagnostics'),
                  ),
                ),
                FilledButton(
                  key: const Key('open-reader-route'),
                  onPressed: () => _openReader(navigatorContext),
                  child: const Text('打开阅读器'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WebViewProbe extends StatefulWidget {
  const WebViewProbe({
    super.key,
    this.routeBackEnabled = false,
    this.resourceProbe,
    this.controlledErrorBaseUrl,
  });

  final bool routeBackEnabled;
  final ReaderResourceProbe? resourceProbe;
  final Uri? controlledErrorBaseUrl;

  @override
  State<WebViewProbe> createState() => _WebViewProbeState();
}

class _WebViewProbeState extends State<WebViewProbe>
    with WidgetsBindingObserver {
  static final Uri _fixtureUrl = Uri.parse('https://fixture.invalid/article');
  late WebViewController _controller;
  int _browserInstanceId = 0;
  late final ReaderProbeCallbacks _callbacks;
  String _lifecycle = 'resumed';
  final List<String> _lifecycleEvents = [];
  bool? _historyBeforeReplacement;
  Offset? _scrollBeforeReplacement;
  bool? _currentHistory;
  Offset? _currentScroll;
  String? _currentUrl;
  bool? _reloadHistoryBefore;
  bool? _reloadHistoryAfter;
  Offset? _reloadScrollBefore;
  Offset? _reloadScrollAfter;
  bool _historyProbeReady = false;
  int _platformFinishedCount = 0;
  int? _raceIgnoredBaseline;
  int _webHistoryBackCount = 0;
  int _blockedRoutePopCount = 0;
  bool _backBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.resourceProbe?.readerMounted();
    _callbacks = ReaderProbeCallbacks(
      onEvent: (event) => debugPrint('WEBVIEW_PROBE $event'),
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    _replaceController(reason: 'initial', notify: false);
  }

  @override
  void dispose() {
    _callbacks.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.resourceProbe?.readerDisposed();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    debugPrint('WEBVIEW_PROBE lifecycle=${state.name}');
    setState(() {
      _lifecycle = state.name;
      _lifecycleEvents.add(state.name);
      if (_lifecycleEvents.length > 8) _lifecycleEvents.removeAt(0);
    });
    widget.resourceProbe?.lifecycleChanged(state);
  }

  Future<void> _replaceController({
    required String reason,
    bool notify = true,
    bool raceFixture = false,
    Uri? requestUrl,
    Uri? subresourceUrl,
  }) async {
    final oldController = _browserInstanceId > 0 ? _controller : null;
    // Invalidate the old attempt before ANY awaited platform operation.
    // Asset URLs contain platform-specific bundle paths. Only this new
    // instance's first pageStarted callback binds the exact expected URL.
    // The race fixture instead uses one known URL on both old and new views.
    final id = raceFixture || subresourceUrl != null
        ? _callbacks.begin(_fixtureUrl)
        : requestUrl != null
        ? _callbacks.begin(requestUrl)
        : _callbacks.beginWithPlatformUrl();
    _browserInstanceId = id;
    final controller = WebViewController();
    _controller = controller;
    if (notify && mounted) setState(() {});
    if (oldController != null) {
      unawaited(_observePreviousController(oldController, id));
    }
    try {
      await controller.setJavaScriptMode(JavaScriptMode.disabled);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) =>
              _callbacks.pageStarted(id, url, source: 'platform'),
          onProgress: (value) =>
              _callbacks.onProgress(id, value, source: 'platform'),
          onPageFinished: (url) => _onPlatformFinished(id, url, controller),
          onWebResourceError: (error) => _callbacks.pageFailed(
            id,
            error.url,
            isMainFrame: error.isForMainFrame,
            source:
                'platform[type=${error.errorType?.name} code=${error.errorCode}]',
            kind: _failureKind(error.errorType),
          ),
          onHttpError: (error) => _callbacks.httpFailed(
            id,
            requestUrl: error.request?.uri,
            statusCode: error.response?.statusCode ?? -1,
            source: 'platform',
          ),
        ),
      );
      if (!mounted || id != _browserInstanceId) return;
      if (subresourceUrl != null) {
        await controller.loadHtmlString(
          '<!doctype html><title>readable error fixture</title>'
          '<h1>readable main page</h1><img src="$subresourceUrl">',
          baseUrl: _fixtureUrl.toString(),
        );
      } else if (requestUrl != null) {
        await controller.loadRequest(requestUrl);
      } else if (raceFixture) {
        await controller.loadHtmlString(
          _largePage(),
          baseUrl: _fixtureUrl.toString(),
        );
      } else {
        await controller.loadFlutterAsset('assets/reader_first.html');
      }
    } on Object {
      _callbacks.pageFailed(
        id,
        _fixtureUrl.toString(),
        isMainFrame: true,
        source: 'setup-exception',
      );
    }
  }

  ReaderFailureKind _failureKind(WebResourceErrorType? type) {
    return switch (type) {
      WebResourceErrorType.failedSslHandshake => ReaderFailureKind.tls,
      WebResourceErrorType.webContentProcessTerminated ||
      WebResourceErrorType.webViewInvalidated => ReaderFailureKind.renderer,
      WebResourceErrorType.timeout => ReaderFailureKind.timeout,
      _ => ReaderFailureKind.network,
    };
  }

  Future<void> _loadHttpMainFailure() async {
    final base = widget.controlledErrorBaseUrl;
    if (base == null) return;
    await _replaceController(
      reason: 'http-main-error',
      requestUrl: base.resolve('/main-500'),
    );
  }

  Future<void> _loadSubresourceFailure() async {
    final base = widget.controlledErrorBaseUrl;
    if (base == null) return;
    await _replaceController(
      reason: 'subresource-error',
      subresourceUrl: base.resolve('/missing.png'),
    );
  }

  Future<void> _loadTlsFailure() async {
    final base = widget.controlledErrorBaseUrl;
    if (base == null) return;
    await _replaceController(
      reason: 'tls-error',
      requestUrl: base.replace(scheme: 'https').resolve('/tls'),
    );
  }

  Future<void> _observePreviousController(
    WebViewController controller,
    int id,
  ) async {
    try {
      final history = await controller.canGoBack();
      final scroll = await controller.getScrollPosition();
      if (!mounted || id != _browserInstanceId) return;
      setState(() {
        _historyBeforeReplacement = history;
        _scrollBeforeReplacement = scroll;
      });
    } on Object {
      // Optional observation is not a passed history/scroll assertion.
    }
  }

  Future<void> _onPlatformFinished(
    int id,
    String url,
    WebViewController controller,
  ) async {
    if (mounted) {
      setState(() => _platformFinishedCount++);
    }
    await _callbacks.pageFinished(
      id,
      url,
      controller.canGoBack,
      source: 'platform',
    );
    if (id == _browserInstanceId) {
      await _observeCurrentController(controller, id);
    }
  }

  Future<void> _observeCurrentController(
    WebViewController controller,
    int id,
  ) async {
    try {
      final history = await controller.canGoBack();
      final scroll = await controller.getScrollPosition();
      final url = await controller.currentUrl();
      if (!mounted || id != _browserInstanceId) return;
      setState(() {
        _currentHistory = history;
        _currentScroll = scroll;
        _currentUrl = url;
      });
    } on Object {
      // The platform observation stays unavailable instead of being guessed.
    }
  }

  Future<void> _establishHistoryAndScroll() async {
    final controller = _controller;
    final id = _browserInstanceId;
    _historyProbeReady = false;
    final finishBefore = _platformFinishedCount;
    await controller.loadFlutterAsset('assets/reader_second.html');
    for (
      var attempt = 0;
      attempt < 50 && _platformFinishedCount == finishBefore;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    for (var attempt = 0; attempt < 5; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await controller.scrollTo(0, 640);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _observeCurrentController(controller, id);
      if ((_currentScroll?.dy ?? 0) > 0) break;
    }
    if (!mounted || id != _browserInstanceId) return;
    setState(
      () => _historyProbeReady =
          _currentHistory == true && (_currentScroll?.dy ?? 0) > 0,
    );
  }

  Future<void> _openSecondPage() async {
    await _controller.loadHtmlString(_page('second'));
  }

  Future<void> _reloadSameController() async {
    final controller = _controller;
    final id = _browserInstanceId;
    _reloadHistoryBefore = await controller.canGoBack();
    _reloadScrollBefore = await controller.getScrollPosition();
    await controller.reload();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted || id != _browserInstanceId) return;
    _reloadHistoryAfter = await controller.canGoBack();
    _reloadScrollAfter = await controller.getScrollPosition();
    await _observeCurrentController(controller, id);
    if (mounted && id == _browserInstanceId) setState(() {});
  }

  Future<void> _raceAndReplace() async {
    _raceIgnoredBaseline = _callbacks.snapshot.ignoredCallbacks;
    final oldController = _controller;
    unawaited(
      oldController.loadHtmlString(
        _largePage(),
        baseUrl: _fixtureUrl.toString(),
      ),
    );
    await _replaceController(reason: 'race-replacement', raceFixture: true);
  }

  Future<void> _goBackInWebHistory() async {
    if (_backBusy) return;
    final controller = _controller;
    final id = _browserInstanceId;
    final canGoBack = await controller.canGoBack();
    if (!mounted || id != _browserInstanceId || !canGoBack) return;
    final finishBefore = _platformFinishedCount;
    setState(() => _backBusy = true);
    try {
      await controller.goBack();
      for (
        var attempt = 0;
        attempt < 50 && _platformFinishedCount == finishBefore;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await _observeCurrentController(controller, id);
      if (!mounted || id != _browserInstanceId) return;
      setState(() {
        _webHistoryBackCount++;
        _historyProbeReady = false;
      });
      widget.resourceProbe?.webHistoryBack();
    } finally {
      if (mounted && id == _browserInstanceId) {
        setState(() => _backBusy = false);
      }
    }
  }

  Future<void> _handleTopBarBack() async {
    if (await _controller.canGoBack()) {
      await _goBackInWebHistory();
      return;
    }
    if (mounted) await Navigator.of(context).maybePop();
  }

  void _handleRoutePop(bool didPop) {
    final action = decideReaderBack(
      didPop: didPop,
      webViewCanGoBack: _currentHistory == true,
    );
    if (action != ReaderBackAction.webHistoryBack) return;
    setState(() => _blockedRoutePopCount++);
    unawaited(_goBackInWebHistory());
  }

  static String _page(String label) =>
      '''
<!doctype html>
<html>
  <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
  <body style="font-family: sans-serif; min-height: 1800px; padding: 24px">
    <h1>WanAndroid Stage 0</h1>
    <p id="page">$label controlled document</p>
    <p>This page contains no JavaScript bridge and performs no network request.</p>
    <p>The test driver opens a second embedded data document.</p>
    <div style="height: 1100px"></div>
    <h2 id="stage0-second">second anchor</h2>
    <div style="height: 700px"></div>
  </body>
</html>
''';

  static String _largePage() =>
      '<!doctype html><meta name="viewport" content="width=device-width">'
      '<title>race fixture</title>${List<String>.filled(12000, '<p>controlled late callback fixture</p>').join()}';

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.routeBackEnabled,
        leading: widget.routeBackEnabled
            ? IconButton(
                key: const Key('reader-top-back'),
                onPressed: _backBusy ? null : _handleTopBarBack,
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        title: const Text('WebView Stage 0'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_callbacks.status, key: const Key('status')),
                Text(
                  'lifecycle=$_lifecycle ignored=${_callbacks.snapshot.ignoredCallbacks} '
                  'lifecycleEvents=${_lifecycleEvents.join(",")} '
                  'phase=${_callbacks.snapshot.phase.name} '
                  'failure=${_callbacks.pageFailureKind?.name} '
                  'diagnosticFailures=${_callbacks.diagnosticFailures} '
                  'historyProbeWrites=${_callbacks.historyProbeWrites} '
                  'historyBefore=$_historyBeforeReplacement '
                  'scrollBefore=$_scrollBeforeReplacement '
                  'currentHistory=$_currentHistory currentScroll=$_currentScroll '
                  'currentUrlScheme=${Uri.tryParse(_currentUrl ?? '')?.scheme} '
                  'currentUrlLength=${_currentUrl?.length} '
                  'historyProbeReady=$_historyProbeReady '
                  'reloadHistory=$_reloadHistoryBefore→$_reloadHistoryAfter '
                  'reloadScroll=$_reloadScrollBefore→$_reloadScrollAfter '
                  'platformFinished=$_platformFinishedCount '
                  'webBacks=$_webHistoryBackCount '
                  'blockedPops=$_blockedRoutePopCount backBusy=$_backBusy '
                  'raceIgnored=${_raceIgnoredBaseline == null ? null : _callbacks.snapshot.ignoredCallbacks - _raceIgnoredBaseline!}',
                  key: const Key('diagnostics'),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _callbacks.trace.isEmpty ? '' : _callbacks.trace.last,
                  key: const Key('callback-trace'),
                ),
                Offstage(
                  offstage: true,
                  child: Text(
                    _callbacks.trace.join('\n'),
                    key: const Key('callback-trace-all'),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilledButton(
                        key: const Key('open-second'),
                        onPressed: _openSecondPage,
                        child: const Text('打开第二页'),
                      ),
                      FilledButton.tonal(
                        key: const Key('establish-history'),
                        onPressed: _establishHistoryAndScroll,
                        child: const Text('建立历史与滚动'),
                      ),
                      FilledButton.tonal(
                        key: const Key('reload-same'),
                        onPressed: _reloadSameController,
                        child: const Text('同实例刷新'),
                      ),
                      FilledButton.tonal(
                        key: const Key('replace-controller'),
                        onPressed: () =>
                            _replaceController(reason: 'replacement'),
                        child: const Text('重建刷新 / 超时重试'),
                      ),
                      FilledButton.tonal(
                        key: const Key('race-replace'),
                        onPressed: _raceAndReplace,
                        child: const Text('旧实例竞态'),
                      ),
                      if (widget.controlledErrorBaseUrl != null) ...[
                        FilledButton.tonal(
                          key: const Key('http-main-error'),
                          onPressed: _loadHttpMainFailure,
                          child: const Text('主框架HTTP错误'),
                        ),
                        FilledButton.tonal(
                          key: const Key('subresource-error'),
                          onPressed: _loadSubresourceFailure,
                          child: const Text('子资源错误'),
                        ),
                        FilledButton.tonal(
                          key: const Key('tls-error'),
                          onPressed: _loadTlsFailure,
                          child: const Text('TLS错误'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: WebViewWidget(
              key: ValueKey<int>(_browserInstanceId),
              controller: _controller,
            ),
          ),
        ],
      ),
    );
    if (!widget.routeBackEnabled) return scaffold;
    return PopScope<void>(
      canPop: _currentHistory != true && !_backBusy,
      onPopInvokedWithResult: (didPop, result) => _handleRoutePop(didPop),
      child: scaffold,
    );
  }
}
