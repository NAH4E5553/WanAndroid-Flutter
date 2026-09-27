import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wanandroid_flutter/src/app/app.dart';
import 'package:wanandroid_flutter/src/app/bootstrap/app_dependencies.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/avatar_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/search_suggestions_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_avatar_repository.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_file_storage.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_image_normalization_gateway.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_image_processor.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/features/topics/view_model/topics_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';
import 'package:wanandroid_flutter/src/model/search_history.dart';

import '../test/support/fake_avatar_dependencies.dart';
import '../test/support/fixed_topic_repository.dart';

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  final Duration step = const Duration(milliseconds: 200);
  for (int waited = 0; waited < 10000; waited += step.inMilliseconds) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Expected widget did not appear: $finder');
}

Future<void> _settle(WidgetTester tester) async {
  // Fixed-duration pumps: the home carousel animates periodically, so
  // pumpAndSettle can wait forever. Explicit pumps keep the entry deterministic.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Waits for the target, lets the page transition finish, then taps. Tapping
/// during a route transition can derive an off-screen hit point.
Future<void> _tapWhenReady(WidgetTester tester, Finder finder) async {
  await _waitFor(tester, finder);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder, warnIfMissed: false);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('stage 5 UI-07: theme, guest gates and controlled login', (
    tester,
  ) async {
    final _ControlledAuthRepository auth = _ControlledAuthRepository();
    final AppDependencies dependencies = buildAppDependencies();
    final ThemeController theme = dependencies.themeController;
    await theme.load();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeControllerProvider.overrideWithValue(theme),
          authRepositoryProvider.overrideWithValue(auth),
          collectionRepositoryProvider.overrideWithValue(
            dependencies.collectionRepository,
          ),
          articleRepositoryProvider.overrideWithValue(
            _EmptyArticleRepository(),
          ),
          topicRepositoryProvider.overrideWithValue(
            const FixedTopicRepository(),
          ),
          searchSuggestionsRepositoryProvider.overrideWithValue(
            _EmptySearchRepository(),
          ),
          avatarRepositoryProvider.overrideWithValue(
            dependencies.avatarRepository,
          ),
        ],
        child: const WanAndroidApp(),
      ),
    );
    await _settle(tester);

    // Profile tab shows the guest state and entries.
    await tester.tap(find.text('我的'));
    await _waitFor(tester, find.text('未登录'));
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('外观与主题'), findsOneWidget);

    // Theme settings apply a palette immediately.
    await tester.tap(find.text('外观与主题'));
    await _settle(tester);
    expect(find.text('配色风格'), findsOneWidget);
    await tester.tap(find.text('莓果玫瑰'));
    await _settle(tester);
    expect(theme.palette, WanPalette.berryRose);

    // The collections screen gates on login while the session is guest.
    await tester.tap(find.byTooltip('返回').last);
    await _settle(tester);
    await tester.tap(find.text('我的收藏'));
    await _settle(tester);
    expect(find.text('请登录后查看收藏'), findsOneWidget);

    // UI-07: a fixed Fake login traverses route -> ViewModel -> Repository.
    await tester.tap(find.byTooltip('返回').last);
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await _waitFor(tester, find.textContaining('欢迎登录 WanAndroid'));
    await tester.enterText(
      find.widgetWithText(TextField, '请输入手机号'),
      '13800138000',
    );
    await tester.enterText(find.widgetWithText(TextField, '请输入密码'), 'secret');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, '登录'));
    await tester.tap(find.widgetWithText(ElevatedButton, '登录'));
    await tester.pump();
    expect(find.text('正在登录…'), findsOneWidget);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(auth.loginCalls, 1);

    auth.completeLogin();
    await _waitFor(tester, find.text('fixture-user'));
    expect(find.text('fixture-user'), findsOneWidget);
  });

  testWidgets('stage 5 UI-07: leaving login cancels the in-flight request', (
    tester,
  ) async {
    final _ControlledAuthRepository auth = _ControlledAuthRepository();
    final AppDependencies dependencies = buildAppDependencies();
    final ThemeController theme = dependencies.themeController;
    await theme.load();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeControllerProvider.overrideWithValue(theme),
          authRepositoryProvider.overrideWithValue(auth),
          collectionRepositoryProvider.overrideWithValue(
            dependencies.collectionRepository,
          ),
          articleRepositoryProvider.overrideWithValue(
            _EmptyArticleRepository(),
          ),
          topicRepositoryProvider.overrideWithValue(
            const FixedTopicRepository(),
          ),
          searchSuggestionsRepositoryProvider.overrideWithValue(
            _EmptySearchRepository(),
          ),
          avatarRepositoryProvider.overrideWithValue(
            dependencies.avatarRepository,
          ),
        ],
        child: const WanAndroidApp(),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('我的'));
    await _waitFor(tester, find.text('未登录'));
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await _waitFor(tester, find.textContaining('欢迎登录 WanAndroid'));
    await tester.enterText(
      find.widgetWithText(TextField, '请输入手机号'),
      '13800138000',
    );
    await tester.enterText(find.widgetWithText(TextField, '请输入密码'), 'secret');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, '登录'));
    await tester.tap(find.widgetWithText(ElevatedButton, '登录'));
    await tester.pump();
    expect(auth.loginCalls, 1);

    await tester.binding.handlePopRoute();
    await _waitFor(tester, find.text('未登录'));
    expect(auth.cancellation?.isCancelled, isTrue);
    auth.completeLogin();
    await _settle(tester);
    expect(find.text('未登录'), findsOneWidget);
  });

  testWidgets('stage 5 UI-08/AVATAR: local avatar flow on device', (
    tester,
  ) async {
    final _ControlledAuthRepository auth = _ControlledAuthRepository();
    auth.authenticated = true;
    auth.notifyListeners();
    final AppDependencies dependencies = buildAppDependencies();
    final ThemeController theme = dependencies.themeController;
    await theme.load();

    // 固定 512×512 源图写入设备临时目录，作为假选图通道的返回。
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 512, 512),
      ui.Paint()..color = const ui.Color(0xFF3366CC),
    );
    final ui.Picture picture = recorder.endRecording();
    final ui.Image rendered = await picture.toImage(512, 512);
    final ByteData? pngBytes = await rendered.toByteData(
      format: ui.ImageByteFormat.png,
    );
    rendered.dispose();
    final Directory tempDir = await getTemporaryDirectory();
    final File sourceFile = File(
      '${tempDir.path}/avatar_fixed_source_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await sourceFile.writeAsBytes(
      pngBytes!.buffer.asUint8List(
        pngBytes.offsetInBytes,
        pngBytes.lengthInBytes,
      ),
    );

    final FakeAvatarImageSourceGateway sourceGateway =
        FakeAvatarImageSourceGateway()
          ..enqueuePick(AvatarPickOutcome.ready(sourceFile.path));
    final FakeAvatarGalleryGateway galleryGateway = FakeAvatarGalleryGateway();
    final DefaultAvatarRepository avatarRepository = DefaultAvatarRepository(
      authRepository: auth,
      sourceGateway: sourceGateway,
      galleryGateway: galleryGateway,
      normalizationGateway: const CopyingAvatarImageNormalizationGateway(),
      processor: const UiAvatarImageProcessor(),
      storage: AvatarFileStorage(
        directories: const PathProviderAvatarDirectories(),
        excludeFromBackup: galleryGateway.excludeFromBackup,
      ),
    );
    await avatarRepository.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeControllerProvider.overrideWithValue(theme),
          authRepositoryProvider.overrideWithValue(auth),
          collectionRepositoryProvider.overrideWithValue(
            dependencies.collectionRepository,
          ),
          articleRepositoryProvider.overrideWithValue(
            _EmptyArticleRepository(),
          ),
          topicRepositoryProvider.overrideWithValue(
            const FixedTopicRepository(),
          ),
          searchSuggestionsRepositoryProvider.overrideWithValue(
            _EmptySearchRepository(),
          ),
          avatarRepositoryProvider.overrideWithValue(avatarRepository),
        ],
        child: const WanAndroidApp(),
      ),
    );
    await _settle(tester);

    // 个人中心：头像入口（已验证）。
    await tester.tap(find.text('我的'));
    await _waitFor(
      tester,
      find.byKey(const ValueKey<String>('profile-avatar-entry')),
    );

    // 查看页。
    await tester.tap(
      find.byKey(const ValueKey<String>('profile-avatar-entry')),
    );
    await _waitFor(
      tester,
      find.byKey(const ValueKey<String>('avatar-viewer-more')),
    );

    // 弹框 → 拍照（假通道立即返回固定图）→ 调整页。
    await _tapWhenReady(
      tester,
      find.byKey(const ValueKey<String>('avatar-viewer-more')),
    );
    await _waitFor(tester, find.text('拍照'));
    await tester.tap(find.text('拍照'));
    await _waitFor(tester, find.text('调整头像'));

    // 完成 → 真实设备文件原子提交 → 返回查看页。
    await _tapWhenReady(tester, find.text('完成'));
    await _waitFor(
      tester,
      find.byKey(const ValueKey<String>('avatar-viewer-more')),
    );
    expect(avatarRepository.view().customAvailable, isTrue);
    expect(avatarRepository.view().customAvatarPath, isNotNull);

    // 返回个人中心：头像区显示自定义图片。
    await _tapWhenReady(
      tester,
      find.byKey(const ValueKey<String>('avatar-viewer-back')),
    );
    await _waitFor(tester, find.text('我的内容'));
    // 精确断言头像入口内的自定义图片（查看页退出转场中的 Image 不计入）。
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('profile-avatar-entry')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );

    // 仓储已在候选复制后清理系统返回的临时源文件（生产行为），此处容错删除。
    if (sourceFile.existsSync()) {
      sourceFile.deleteSync();
    }
  });

  testWidgets('stage 5 AVATAR-14: app reconstruction restores and navigates', (
    tester,
  ) async {
    final _ControlledAuthRepository auth = _ControlledAuthRepository();
    auth.authenticated = true;
    auth.notifyListeners();
    final AppDependencies dependencies = buildAppDependencies();
    final ThemeController theme = dependencies.themeController;
    await theme.load();

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 512, 512),
      ui.Paint()..color = const ui.Color(0xFF3366CC),
    );
    final ui.Picture picture = recorder.endRecording();
    final ui.Image rendered = await picture.toImage(512, 512);
    final ByteData? pngBytes = await rendered.toByteData(
      format: ui.ImageByteFormat.png,
    );
    rendered.dispose();
    final Directory tempDir = await getTemporaryDirectory();
    final File sourceFile = File(
      '${tempDir.path}/avatar_pending_source_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await sourceFile.writeAsBytes(
      pngBytes!.buffer.asUint8List(
        pngBytes.offsetInBytes,
        pngBytes.lengthInBytes,
      ),
    );

    const AvatarIdentity identity42 = AvatarIdentity(
      userId: 42,
      accountVersionKey: 'integration:1',
    );
    final FakeAvatarImageSourceGateway sourceGateway =
        FakeAvatarImageSourceGateway()
          ..enqueuePick(AvatarPickOutcome.ready(sourceFile.path));
    final FakeAvatarGalleryGateway galleryGateway = FakeAvatarGalleryGateway();
    final DefaultAvatarRepository firstRepository = DefaultAvatarRepository(
      authRepository: auth,
      sourceGateway: sourceGateway,
      galleryGateway: galleryGateway,
      normalizationGateway: const CopyingAvatarImageNormalizationGateway(),
      processor: const UiAvatarImageProcessor(),
      storage: AvatarFileStorage(
        directories: const PathProviderAvatarDirectories(),
        excludeFromBackup: galleryGateway.excludeFromBackup,
      ),
    );
    await firstRepository.initialize();

    // 首进程只留下持久化 pending；测试不调用旧 App 的 dispose，等价于
    // 进程被系统终止时没有生命周期收尾。这里不冒充真实 OS kill。
    sourceGateway.pickGate = Completer<void>();
    final Future<AvatarCandidateStart> killedPick = firstRepository
        .startCandidate(source: AvatarSource.camera, identity: identity42);
    unawaited(killedPick);
    await sourceGateway.pickStarted.future;

    // 模拟进程被杀后重启：新仓储实例读取同一持久化 pending；
    // lost data 由假通道按 retrieveLostData 语义重放。
    sourceGateway.lostResult = AvatarPickOutcome.ready(sourceFile.path);
    final DefaultAvatarRepository secondRepository = DefaultAvatarRepository(
      authRepository: auth,
      sourceGateway: sourceGateway,
      galleryGateway: galleryGateway,
      normalizationGateway: const CopyingAvatarImageNormalizationGateway(),
      processor: const UiAvatarImageProcessor(),
      storage: AvatarFileStorage(
        directories: const PathProviderAvatarDirectories(),
        excludeFromBackup: galleryGateway.excludeFromBackup,
      ),
    );
    await secondRepository.initialize();
    expect(secondRepository.hasPendingOperation(), isTrue);

    // 重建生产 App，先让 WanAndroidApp 注册 recoveryReady 监听，再消费
    // lost data；断言导航由生产监听器触发，而不是测试手工 markConsumed。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeControllerProvider.overrideWithValue(theme),
          authRepositoryProvider.overrideWithValue(auth),
          collectionRepositoryProvider.overrideWithValue(
            dependencies.collectionRepository,
          ),
          articleRepositoryProvider.overrideWithValue(
            _EmptyArticleRepository(),
          ),
          topicRepositoryProvider.overrideWithValue(
            const FixedTopicRepository(),
          ),
          searchSuggestionsRepositoryProvider.overrideWithValue(
            _EmptySearchRepository(),
          ),
          avatarRepositoryProvider.overrideWithValue(secondRepository),
        ],
        child: const WanAndroidApp(),
      ),
    );
    await _settle(tester);
    final AvatarCandidateStart recovered = await secondRepository
        .consumeRecoveredOperation(
          identity: const AvatarIdentity(
            userId: 42,
            accountVersionKey: 'integration:1',
          ),
        );
    expect(recovered.status, AvatarCandidateStartStatus.ready);
    expect(secondRepository.view().candidateReady, isTrue);
    await _waitFor(tester, find.text('调整头像'));
    expect(secondRepository.view().recoveryReady, isFalse);
    // 释放被挂起的首实例 pick（其结果按会话失效丢弃）。
    sourceGateway.pickGate!.complete();
    await killedPick;
    if (sourceFile.existsSync()) {
      sourceFile.deleteSync();
    }
  });

  testWidgets('stage 5 AVATAR: native EXIF orientation 6 and 2 normalization', (
    tester,
  ) async {
    final Directory temp = await getTemporaryDirectory();
    final ChannelAvatarImageNormalizationGateway gateway =
        const ChannelAvatarImageNormalizationGateway();

    Future<(int, int, Uint8List)> normalizeAndDecode(
      String name,
      String encoded,
    ) async {
      final File source = File('${temp.path}/$name.jpg');
      final File destination = File('${temp.path}/$name.png');
      await source.writeAsBytes(base64Decode(encoded));
      await gateway.normalizeToPng(
        sourcePath: source.path,
        destinationPath: destination.path,
        maxDimension: UiAvatarImageProcessor.maxSourceDimension,
        maxPixelCount: UiAvatarImageProcessor.maxSourcePixelCount,
        maxFileBytes: UiAvatarImageProcessor.maxSourceFileBytes,
      );
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
        await destination.readAsBytes(),
      );
      final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(
        buffer,
      );
      final ui.Codec codec = await descriptor.instantiateCodec();
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ByteData rgba = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final (int width, int height) = (frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      await source.delete();
      await destination.delete();
      return (
        width,
        height,
        rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
      );
    }

    final (int rotatedWidth, int rotatedHeight, Uint8List _) =
        await normalizeAndDecode('orientation6', _orientation6JpegBase64);
    expect((rotatedWidth, rotatedHeight), (2, 4));

    final (int mirroredWidth, int mirroredHeight, Uint8List mirrored) =
        await normalizeAndDecode('orientation2', _orientation2JpegBase64);
    expect((mirroredWidth, mirroredHeight), (8, 4));
    final int left = (2 * mirroredWidth + 1) * 4;
    final int right = (2 * mirroredWidth + 6) * 4;
    expect(mirrored[left + 2], greaterThan(mirrored[left]), reason: '左侧应为蓝');
    expect(mirrored[right], greaterThan(mirrored[right + 2]), reason: '右侧应为红');
  });
}

const String _orientation6JpegBase64 =
    '/9j/4QAeRXhpZgAASUkqAAgAAAABABIBAwABAAAABgAAAP/gABBKRklGAAEBAABIAEgAAP/hAExFeGlmAABNTQAqAAAACAABh2kABAAAAAEAAAAaAAAAAAADoAEAAwAAAAEAAQAAoAIABAAAAAEAAAAEoAMABAAAAAEAAAACAAAAAP/tADhQaG90b3Nob3AgMy4wADhCSU0EBAAAAAAAADhCSU0EJQAAAAAAENQdjNmPALIE6YAJmOz4Qn7/wAARCAACAAQDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9sAQwACAgICAgIDAgIDBQMDAwUGBQUFBQYIBgYGBgYICggICAgICAoKCgoKCgoKDAwMDAwMDg4ODg4PDw8PDw8PDw8P/9sAQwECAgIEBAQHBAQHEAsJCxAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ/90ABAAB/9oADAMBAAIRAxEAPwD8i/8AhINf/wCglc/9/n/xo/4SDX/+glc/9/n/AMax6K/qg/tQ/9k=';

const String _orientation2JpegBase64 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/4QAiRXhpZgAATU0AKgAAAAgAAQESAAMAAAABAAIAAAAAAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/2wBDAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAARCAAEAAgDAREAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD+aP8Aaq/5kP8A7mj/AN12v9UP9GX/AOc2P+9bv/g9n+1H+kM/84h/95+/+Aof/9k=';

class _ControlledAuthRepository extends ChangeNotifier
    implements AuthRepository {
  final Completer<DataResult<void>> _login = Completer<DataResult<void>>();
  int loginCalls = 0;
  RequestCancellation? cancellation;
  bool authenticated = false;

  void completeLogin() {
    if (_login.isCompleted) return;
    if (cancellation?.isCancelled != true) {
      authenticated = true;
      notifyListeners();
    }
    _login.complete(const DataSuccess<void>(null));
  }

  @override
  AuthStateView view() => AuthStateView(
    loading: false,
    authenticated: authenticated,
    unverified: false,
    expiredNotice: false,
    storageNotice: false,
    displayName: authenticated ? 'fixture-user' : null,
    userId: authenticated ? 42 : null,
    accountVersionKey: authenticated ? 'integration:1' : null,
  );

  @override
  Future<DataResult<void>> login(
    String username,
    String password, {
    RequestCancellation cancellation = const LiveRequestCancellation(),
  }) {
    loginCalls += 1;
    this.cancellation = cancellation;
    return Future.any<DataResult<void>>(<Future<DataResult<void>>>[
      _login.future,
      cancellation.whenCancelled.then<DataResult<void>>(
        (_) => throw const RequestCancelledException(),
      ),
    ]);
  }

  @override
  Future<DataResult<void>> restore() async => const DataSuccess<void>(null);

  @override
  Future<LogoutOutcome> logout() async =>
      LogoutOutcome(generation: 1, remote: const DataSuccess<void>(null));
}

class _EmptyArticleRepository implements ArticleRepository {
  @override
  Future<DataResult<PageResult<Article>>> articles(
    int page,
    RequestCancellation cancellation,
  ) async => DataSuccess<PageResult<Article>>(
    PageResult<Article>(items: <Article>[], nextPage: null),
  );

  @override
  Future<DataResult<PageResult<Article>>> questionPage(
    int page,
    RequestCancellation cancellation,
  ) async => DataSuccess<PageResult<Article>>(
    PageResult<Article>(items: <Article>[], nextPage: null),
  );

  @override
  Future<DataResult<List<Article>>> questions(
    RequestCancellation cancellation,
  ) async => DataSuccess<List<Article>>(<Article>[]);

  @override
  Future<DataResult<PageResult<Article>>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) async => DataSuccess<PageResult<Article>>(
    PageResult<Article>(items: <Article>[], nextPage: null),
  );
}

/// AVATAR-01～08（设备端，固定假通道 + 真实文件存储与处理管线）：
/// 个人中心头像入口 → 查看页 → 弹框 → 拍照（假通道返回固定图）→ 调整页
/// 完成 → 真实设备文件原子提交 → 查看页与个人中心同步显示。
class _EmptySearchRepository implements SearchSuggestionsRepository {
  @override
  Future<SearchHistory> loadHistory() async => const SearchHistory();

  @override
  Future<DataResult<List<String>>> hotKeys(
    RequestCancellation cancellation,
  ) async => DataSuccess<List<String>>(<String>[]);

  @override
  Future<bool> record(String keyword) async => true;

  @override
  Future<bool> clearHistory() async => true;
}
