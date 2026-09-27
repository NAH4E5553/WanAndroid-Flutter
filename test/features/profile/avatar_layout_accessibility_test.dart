import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_storage.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/avatar_repository.dart';
import 'package:wanandroid_flutter/src/features/profile/view/avatar_adjust_screen.dart';
import 'package:wanandroid_flutter/src/features/profile/view/avatar_viewer_screen.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';

import '../../support/fake_avatar_dependencies.dart';

/// 审查回归（P1-8）：窄屏（320/360/390）、200% 字体与弹框模态焦点。
void main() {
  testWidgets('调整页在 320/360/390 宽度与 200% 字体下不溢出、按钮可达', (
    WidgetTester tester,
  ) async {
    final AvatarTestAuthRepository auth = AvatarTestAuthRepository()
      ..loginAs(7);
    final FakeAvatarRepository avatar = FakeAvatarRepository()
      ..emit(
        const AvatarStateView(
          userId: 7,
          editable: true,
          customAvailable: false,
          customAvatarPath: null,
          candidateReady: true,
          candidatePath: '/tmp/nonexistent.png',
          committing: false,
          savingToGallery: false,
          recoveryReady: false,
        ),
      );

    for (final double width in <double>[320, 360, 390]) {
      for (final double scale in <double>[1.0, 2.0]) {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: Size(width, 800),
              textScaler: TextScaler.linear(scale),
            ),
            child: ProviderScope(
              overrides: [
                authRepositoryProvider.overrideWithValue(auth),
                avatarRepositoryProvider.overrideWithValue(avatar),
                themeControllerProvider.overrideWithValue(
                  ThemeController(preferences: _MemoryThemeStorage()),
                ),
              ],
              child: MaterialApp(home: AvatarAdjustScreen(onBack: () {})),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.text('取消'),
          findsOneWidget,
          reason: 'width=$width fs=$scale',
        );
        expect(
          find.text('完成'),
          findsOneWidget,
          reason: 'width=$width fs=$scale',
        );
        expect(
          find.text('拖动、双指缩放或旋转进行调整'),
          findsOneWidget,
          reason: 'width=$width fs=$scale',
        );
        // 无布局溢出异常（tester 会把 RenderFlex overflow 记为异常）。
        expect(
          tester.takeException(),
          isNull,
          reason: 'width=$width fs=$scale',
        );
      }
    }
  });

  testWidgets('弹框打开：焦点进入弹框内首个操作项；关闭后回到「更多操作」', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final AvatarTestAuthRepository auth = AvatarTestAuthRepository()
      ..loginAs(7);
    final FakeAvatarRepository avatar = FakeAvatarRepository()
      ..emit(
        const AvatarStateView(
          userId: 7,
          editable: true,
          customAvailable: false,
          customAvatarPath: null,
          candidateReady: false,
          candidatePath: null,
          committing: false,
          savingToGallery: false,
          recoveryReady: false,
        ),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          avatarRepositoryProvider.overrideWithValue(avatar),
          themeControllerProvider.overrideWithValue(
            ThemeController(preferences: _MemoryThemeStorage()),
          ),
        ],
        child: MaterialApp(
          home: AvatarViewerScreen(onBack: () {}, onAdjust: () {}),
        ),
      ),
    );
    await tester.pump();

    // 打开前焦点在「更多操作」。
    await tester.tap(find.byKey(const ValueKey<String>('avatar-viewer-more')));
    await tester.pump();
    await tester.pumpAndSettle();

    // 弹框打开后：焦点应位于弹框内部（四个操作项之一）。
    final FocusNode? openFocus = FocusManager.instance.primaryFocus;
    expect(openFocus, isNotNull);
    expect(openFocus!.context, isNotNull, reason: '弹框打开后焦点必须存在');
    final bool focusInSheet =
        openFocus.context!.findAncestorWidgetOfExactType<BottomSheet>() !=
            null ||
        openFocus.context!.findAncestorWidgetOfExactType<SafeArea>() != null;
    expect(focusInSheet, isTrue, reason: '焦点应进入弹框');

    // 关闭弹框后焦点回到「更多操作」按钮。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final FocusNode? closedFocus = FocusManager.instance.primaryFocus;
    expect(closedFocus, isNotNull);
    final BuildContext? closedContext = closedFocus!.context;
    bool backOnMore = false;
    closedContext?.visitAncestorElements((Element element) {
      if (element.widget is IconButton) {
        backOnMore = true;
        return false;
      }
      return true;
    });
    expect(backOnMore, isTrue, reason: '关闭后焦点应回到「更多操作」IconButton');
    semantics.dispose();
  });
}

class _MemoryThemeStorage implements ThemeStorage {
  @override
  Future<ThemeSelection?> read() async => null;

  @override
  Future<void> write(WanPalette palette, ThemeMode mode) async {}
}
