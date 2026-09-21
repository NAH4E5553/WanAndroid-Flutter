# webview_flutter_android local patch

Vendored copy of `webview_flutter_android` **4.14.1** (BSD-3, Copyright 2013
The Flutter Authors, see `LICENSE`). Only the modifications below are local;
everything else is byte-identical to the published package.

## Patch: renderer-death handling (`onRenderProcessGone`)

Upstream has no `onRenderProcessGone` callback as of 4.14.1, so when the
sandboxed WebView renderer dies (system memory reclaim, WebView provider
package update, or renderer crash) the default `WebViewClient` returns
`false` and Android kills the whole app, contradicting the official guidance
in https://developer.android.com/develop/ui/views/layout/webapps/managing-webview#Terminate.

Local changes (search for `WanAndroid Flutter local patch`):

- `android/src/main/java/io/flutter/plugins/webviewflutter/WebViewClientProxyApi.java`:
  `WebViewClientImpl` overrides `onRenderProcessGone` (API 26+), returns
  `true` (app survives), and reports `[String? url, bool didCrash]` over the
  local channel
  `dev.flutter.local_patch.webview_flutter_android/WebViewClient.onRenderProcessGone`
  (`StandardMessageCodec`). API 24/25 never invoke this callback and keep the
  default whole-app kill behavior.
- `lib/src/android_webkit_constants.dart`: synthetic
  `WebViewClientConstants.errorWebContentProcessTerminated = -100`.
- `lib/src/android_webview_controller.dart`: `AndroidNavigationDelegate`
  listens on the channel and surfaces the event as a main-frame
  `WebResourceErrorType.webContentProcessTerminated` `WebResourceError`,
  mirroring how `webview_flutter_wkwebview` reports
  `webViewWebContentProcessDidTerminate`.

## Maintenance

Re-apply this patch whenever the plugin is upgraded; verify presence with the
stage 4 structural check (`tool/verify_stage4.dart`). A matching upstream PR
to flutter/packages is the long-term replacement for this fork.
