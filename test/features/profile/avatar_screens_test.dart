import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_storage.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/features/profile/component/wan_person_icon.dart';
import 'package:wanandroid_flutter/src/features/profile/view/avatar_adjust_screen.dart';
import 'package:wanandroid_flutter/src/features/profile/view/avatar_viewer_screen.dart';
import 'package:wanandroid_flutter/src/features/profile/view/profile_screen.dart'
    show ProfileScreen;
import 'package:wanandroid_flutter/src/features/profile/view_model/avatar_adjust_view_model.dart';
import 'package:wanandroid_flutter/src/features/profile/view_model/avatar_viewer_view_model.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';

import '../../support/fake_avatar_dependencies.dart';

void main() {
  late Directory tempDir;
  late File avatarFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('avatar_widget');
    avatarFile = File('${tempDir.path}/avatar.png');
    await avatarFile.writeAsBytes(
      await renderSolidPng(width: 512, height: 512),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget wrap(
    Widget child, {
    required AvatarTestAuthRepository auth,
    required FakeAvatarRepository avatar,
  }) => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      avatarRepositoryProvider.overrideWithValue(avatar),
      themeControllerProvider.overrideWithValue(
        ThemeController(preferences: _MemoryThemeStorage()),
      ),
    ],
    child: MaterialApp(home: child),
  );

  group('ProfileScreen 头像入口', () {
    testWidgets('游客显示默认徽标，无「查看头像」操作语义', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          ProfileScreen(
            onHistoryTap: () {},
            onCollectionsTap: () {},
            onThemeTap: () {},
            onLoginTap: () {},
            onAvatarTap: () {},
          ),
          auth: AvatarTestAuthRepository(),
          avatar: FakeAvatarRepository(),
        ),
      );
      await tester.pump();

      expect(find.byType(WanPersonIcon), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && widget.properties.label == '查看头像',
        ),
        findsNothing,
      );
    });

    testWidgets('已登录默认头像：徽标可点，读屏「查看头像」', (WidgetTester tester) async {
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
        wrap(
          ProfileScreen(
            onHistoryTap: () {},
            onCollectionsTap: () {},
            onThemeTap: () {},
            onLoginTap: () {},
            onAvatarTap: () {},
          ),
          auth: auth,
          avatar: avatar,
        ),
      );
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && widget.properties.label == '查看头像',
        ),
        findsOneWidget,
      );
      expect(find.byType(WanPersonIcon), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('已登录自定义头像：显示文件并支持点击', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();

      final AvatarTestAuthRepository auth = AvatarTestAuthRepository()
        ..loginAs(7);
      final FakeAvatarRepository avatar = FakeAvatarRepository()
        ..emit(
          AvatarStateView(
            userId: 7,
            editable: true,
            customAvailable: true,
            customAvatarPath: avatarFile.path,
            candidateReady: false,
            candidatePath: null,
            committing: false,
            savingToGallery: false,
            recoveryReady: false,
          ),
        );
      int taps = 0;
      await tester.pumpWidget(
        wrap(
          ProfileScreen(
            onHistoryTap: () {},
            onCollectionsTap: () {},
            onThemeTap: () {},
            onLoginTap: () {},
            onAvatarTap: () => taps += 1,
          ),
          auth: auth,
          avatar: avatar,
        ),
      );
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && widget.properties.label == '查看头像',
        ),
        findsOneWidget,
      );
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && widget.properties.label == '查看头像',
        ),
      );
      await tester.pump();
      expect(taps, 1);
      semantics.dispose();
    });
  });

  group('AvatarViewerScreen', () {
    testWidgets('查看页展示返回与横向三点；默认徽标；无删除/恢复入口', (WidgetTester tester) async {
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
        wrap(
          AvatarViewerScreen(onBack: () {}, onAdjust: () {}),
          auth: auth,
          avatar: avatar,
        ),
      );
      await tester.pump();

      expect(find.byTooltip('返回'), findsOneWidget);
      expect(find.byTooltip('更多操作'), findsOneWidget);
      expect(find.byType(WanPersonIcon), findsOneWidget);
      expect(find.text('恢复默认头像'), findsNothing);
      expect(find.text('删除头像'), findsNothing);
    });

    testWidgets('弹框固定四项：拍照/相册/保存/取消', (WidgetTester tester) async {
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
        wrap(
          AvatarViewerScreen(onBack: () {}, onAdjust: () {}),
          auth: auth,
          avatar: avatar,
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();

      expect(find.text('拍照'), findsOneWidget);
      expect(find.text('从手机相册选择'), findsOneWidget);
      expect(find.text('保存到手机'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('恢复默认头像'), findsNothing);
      expect(find.text('删除头像'), findsNothing);
    });

    testWidgets('保存成功提示；失败提示不误报成功', (WidgetTester tester) async {
      final AvatarTestAuthRepository auth = AvatarTestAuthRepository()
        ..loginAs(7);
      final FakeAvatarRepository avatar = FakeAvatarRepository()
        ..nextSaveStatus = AvatarGallerySaveStatus.success;
      await tester.pumpWidget(
        wrap(
          AvatarViewerScreen(onBack: () {}, onAdjust: () {}),
          auth: auth,
          avatar: avatar,
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存到手机'));
      await tester.pump();
      expect(find.text('头像已保存到相册'), findsOneWidget);
      expect(avatar.saveCalls, 1);

      // 等待第一条 SnackBar 消失：先完成入场动画，再走完 2 秒计时与退出动画，
      // 避免新提示进入排队。
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      avatar.nextSaveStatus = AvatarGallerySaveStatus.failure;
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存到手机'));
      await tester.pump();
      expect(find.text('头像保存失败，请重试'), findsOneWidget);
    });

    testWidgets('身份变化后保存被拒绝且不调用仓储写入口', (WidgetTester tester) async {
      final AvatarTestAuthRepository auth = AvatarTestAuthRepository();
      final FakeAvatarRepository avatar = FakeAvatarRepository();
      await tester.pumpWidget(
        wrap(
          AvatarViewerScreen(onBack: () {}, onAdjust: () {}),
          auth: auth,
          avatar: avatar,
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存到手机'));
      await tester.pump();
      expect(avatar.saveCalls, 0);
      expect(find.text('头像保存失败，请重试'), findsOneWidget);
    });
  });

  group('AvatarAdjustScreen', () {
    testWidgets('无候选时立即退出并丢弃候选', (WidgetTester tester) async {
      final AvatarTestAuthRepository auth = AvatarTestAuthRepository()
        ..loginAs(7);
      final FakeAvatarRepository avatar = FakeAvatarRepository();
      int backs = 0;
      await tester.pumpWidget(
        wrap(
          AvatarAdjustScreen(onBack: () => backs += 1),
          auth: auth,
          avatar: avatar,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(backs, 1);
      // 卸载页面 → 调整页 ViewModel dispose → 丢弃候选。
      await tester.pumpWidget(const SizedBox());
      expect(avatar.discardCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('有候选时展示顶栏与裁切引导', (WidgetTester tester) async {
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
      await tester.pumpWidget(
        wrap(
          AvatarAdjustScreen(onBack: () {}),
          auth: auth,
          avatar: avatar,
        ),
      );
      await tester.pump();

      expect(find.text('取消'), findsOneWidget);
      expect(find.text('调整头像'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('拖动、双指缩放或旋转进行调整'), findsOneWidget);
    });
  });

  group('AvatarViewerViewModel / AvatarAdjustViewModel', () {
    test('提交成功后查看页与调整页状态同步刷新；游客不可编辑', () async {
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
            candidatePath: '/tmp/candidate.png',
            committing: false,
            savingToGallery: false,
            recoveryReady: false,
          ),
        );
      final ProviderContainer container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          avatarRepositoryProvider.overrideWithValue(avatar),
        ],
      );
      addTearDown(container.dispose);

      final AvatarViewerState viewer = container.read(
        avatarViewerViewModelProvider,
      );
      expect(viewer.avatar.candidateReady, isTrue);
      expect(viewer.identity?.userId, 7);

      // 仓储事实更新（提交成功）→ 两个 ViewModel 都拿到新状态。
      avatar.emit(
        const AvatarStateView(
          userId: 7,
          editable: true,
          customAvailable: true,
          customAvatarPath: '/avatars/avatar_7_1.png',
          candidateReady: false,
          candidatePath: null,
          committing: false,
          savingToGallery: false,
          recoveryReady: false,
        ),
      );
      expect(
        container.read(avatarViewerViewModelProvider).avatar.customAvailable,
        isTrue,
      );
      final AvatarAdjustState adjust = container.read(
        avatarAdjustViewModelProvider,
      );
      expect(adjust.candidateReady, isFalse);
      // 调整页 dispose 时丢弃候选由仓储承担，这里断言无第二份状态。
      expect(adjust.committing, isFalse);
      // 游客会话：身份缺失，不可编辑。
      auth.simulateLogout();
      avatar.emit(
        const AvatarStateView(
          userId: null,
          editable: false,
          customAvailable: false,
          customAvatarPath: null,
          candidateReady: false,
          candidatePath: null,
          committing: false,
          savingToGallery: false,
          recoveryReady: false,
        ),
      );
      expect(
        container.read(avatarViewerViewModelProvider).avatar.editable,
        isFalse,
      );
      expect(container.read(avatarViewerViewModelProvider).identity, isNull);
    });
  });
}

/// 内存主题存储（ProfileViewModel 依赖）。
class _MemoryThemeStorage implements ThemeStorage {
  @override
  Future<ThemeSelection?> read() async => null;

  @override
  Future<void> write(WanPalette palette, ThemeMode mode) async {}
}
