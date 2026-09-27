import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/providers.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/avatar_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_avatar_repository.dart';
import 'package:wanandroid_flutter/src/features/profile/view_model/avatar_viewer_view_model.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';

import 'avatar_repository_test.dart' show Harness;

/// 审查回归（2026-09-27）：每条对应一个此前未被门禁拦截的生产缺陷，
/// 全部先在旧实现上失败后补齐。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P1-2 处理中切号：busy 必须复位', () {
    test('处理期间切号：返回 identityChanged 且 committing 复位', () async {
      final Harness harness = await Harness.setup();
      harness.processor.renderDelay = const Duration(milliseconds: 60);
      await harness.startCandidateReady();

      final Future<AvatarCommitOutcome> committing = harness.repository
          .commitCandidate(identity: harness.identityA, params: harness.params);
      // 处理进行中切号（accountVersionKey 递增）。
      await Future<void>.delayed(const Duration(milliseconds: 10));
      harness.auth.loginAs(2);

      final AvatarCommitOutcome outcome = await committing;
      expect(outcome.status, AvatarCommitStatus.identityChanged);
      // 核心断言：busy 不被遗留。
      expect(harness.repository.view().committing, isFalse);
    });

    test('处理期间退出：返回 identityChanged 且 committing 复位', () async {
      final Harness harness = await Harness.setup();
      harness.processor.renderDelay = const Duration(milliseconds: 60);
      await harness.startCandidateReady();

      final Future<AvatarCommitOutcome> committing = harness.repository
          .commitCandidate(identity: harness.identityA, params: harness.params);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      harness.auth.simulateLogout();

      final AvatarCommitOutcome outcome = await committing;
      expect(outcome.status, AvatarCommitStatus.identityChanged);
      expect(harness.repository.view().committing, isFalse);
    });
  });

  group('P1-4 候选验证与源清理', () {
    test('损坏图片：不进入调整页（failed），调整页不会拿到候选', () async {
      final Harness harness = await Harness.setup();
      final File bad = File(
        '${(await harness.storage.candidateDirectory())}/bad_source.bin',
      );
      await bad.writeAsBytes(<int>[1, 2, 3, 4, 5]);
      harness.processor.decodeFails = true;
      harness.sourceGateway.enqueuePick(AvatarPickOutcome.ready(bad.path));

      final AvatarCandidateStart result = await harness.repository
          .startCandidate(
            source: AvatarSource.gallery,
            identity: harness.identityA,
          );

      expect(result.status, AvatarCandidateStartStatus.failed);
      expect(harness.repository.view().candidateReady, isFalse);
    });

    test('超大图片：头部校验拒绝，不进入调整页（防 FileImage 全尺寸解码 OOM）', () async {
      final Harness harness = await Harness.setup();
      harness.processor.oversized = true;
      harness.sourceGateway.enqueuePick(
        AvatarPickOutcome.ready(harness.externalSourcePath),
      );

      final AvatarCandidateStart result = await harness.repository
          .startCandidate(
            source: AvatarSource.gallery,
            identity: harness.identityA,
          );

      expect(result.status, AvatarCandidateStartStatus.failed);
      expect(harness.repository.view().candidateReady, isFalse);
    });

    test('选图会话失效：页面销毁（discard）后迟到的 ready 被丢弃', () async {
      final Harness harness = await Harness.setup();
      harness.sourceGateway.pickGate = Completer<void>();
      harness.sourceGateway.enqueuePick(
        AvatarPickOutcome.ready(harness.externalSourcePath),
      );

      final Future<AvatarCandidateStart> pending = harness.repository
          .startCandidate(
            source: AvatarSource.gallery,
            identity: harness.identityA,
          );
      unawaited(pending);
      // 页面销毁语义：丢弃候选使会话失效。
      harness.repository.discardCandidate();
      harness.sourceGateway.pickGate!.complete();

      final AvatarCandidateStart result = await pending;
      expect(result.status, AvatarCandidateStartStatus.cancelled);
      expect(harness.repository.view().candidateReady, isFalse);
    });

    test('查看页 ViewModel 销毁：生产生命周期使迟到结果和 pending 失效', () async {
      final Harness harness = await Harness.setup();
      harness.sourceGateway.pickGate = Completer<void>();
      harness.sourceGateway.enqueuePick(
        AvatarPickOutcome.ready(harness.externalSourcePath),
      );
      final ProviderContainer container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(harness.auth),
          avatarRepositoryProvider.overrideWithValue(harness.repository),
        ],
      );
      final ProviderSubscription<AvatarViewerState> subscription = container
          .listen<AvatarViewerState>(
            avatarViewerViewModelProvider,
            (_, _) {},
            fireImmediately: true,
          );
      final Future<AvatarViewerAction> pending = container
          .read(avatarViewerViewModelProvider.notifier)
          .startCandidate(AvatarSource.gallery);
      await harness.sourceGateway.pickStarted.future;

      subscription.close();
      await container.pump();
      harness.sourceGateway.pickGate!.complete();

      expect(await pending, AvatarViewerAction.cancelled);
      expect(harness.repository.view().candidateReady, isFalse);
      expect(
        await harness.storage.fileExists(
          await harness.storage.pendingFilePath(),
        ),
        isFalse,
      );
      container.dispose();
    });

    test('头部校验等待期间切号：归一化不启动且旧账号候选不发布', () async {
      final Harness harness = await Harness.setup();
      harness.processor.ensureGate = Completer<void>();
      harness.sourceGateway.enqueuePick(
        AvatarPickOutcome.ready(harness.externalSourcePath),
      );
      final Future<AvatarCandidateStart> pending = harness.repository
          .startCandidate(
            source: AvatarSource.gallery,
            identity: harness.identityA,
          );
      await harness.processor.ensureStarted.future;
      harness.auth.loginAs(2);
      harness.processor.ensureGate!.complete();

      expect(
        (await pending).status,
        AvatarCandidateStartStatus.identityChanged,
      );
      expect(harness.normalizationGateway.calls, 0);
      expect(harness.repository.view().candidateReady, isFalse);
    });

    test('原生归一等待期间切号：已生成文件被清理且不发布', () async {
      final Harness harness = await Harness.setup();
      harness.normalizationGateway.gate = Completer<void>();
      harness.sourceGateway.enqueuePick(
        AvatarPickOutcome.ready(harness.externalSourcePath),
      );
      final Future<AvatarCandidateStart> pending = harness.repository
          .startCandidate(
            source: AvatarSource.gallery,
            identity: harness.identityA,
          );
      await harness.normalizationGateway.started.future;
      harness.auth.loginAs(2);
      harness.normalizationGateway.gate!.complete();

      expect(
        (await pending).status,
        AvatarCandidateStartStatus.identityChanged,
      );
      expect(harness.repository.view().candidateReady, isFalse);
      final Directory candidates = Directory(
        await harness.storage.candidateDirectory(),
      );
      expect(await candidates.list().isEmpty, isTrue);
    });

    test('并发选图：第二次返回 busy，不覆盖唯一 pending', () async {
      final Harness harness = await Harness.setup();
      harness.sourceGateway.pickGate = Completer<void>();
      harness.sourceGateway.enqueuePick(
        AvatarPickOutcome.ready(harness.externalSourcePath),
      );
      final Future<AvatarCandidateStart> firstFuture = harness.repository
          .startCandidate(
            source: AvatarSource.gallery,
            identity: harness.identityA,
          );
      unawaited(firstFuture);

      final AvatarCandidateStart second = await harness.repository
          .startCandidate(
            source: AvatarSource.camera,
            identity: harness.identityA,
          );

      expect(second.status, AvatarCandidateStartStatus.busy);
      harness.sourceGateway.pickGate!.complete();
      final AvatarCandidateStart firstOutcome = await firstFuture;
      expect(firstOutcome.status, AvatarCandidateStartStatus.ready);
      // 全程只打开了一个系统页。
      expect(harness.sourceGateway.pickCalls, 1);
    });
  });

  group('其他：保存到相册读取期间切号', () {
    test('渲染等待期间切号：不写入库', () async {
      final Harness harness = await Harness.setup();
      // 无已提交头像 → 走 defaultAvatarPng 渲染路径；渲染等待期间切号，
      // 写入库前的身份复核必须拦截。
      final AvatarGallerySaveOutcome outcome = await harness.repository
          .saveCurrentToGallery(
            identity: harness.identityA,
            defaultAvatarPng: () async {
              await Future<void>.delayed(const Duration(milliseconds: 40));
              harness.auth.loginAs(2);
              return <int>[1, 2, 3];
            },
          );

      expect(outcome.status, AvatarGallerySaveStatus.failure);
      expect(harness.galleryGateway.savedFileNames, isEmpty);
    });
  });

  group('P1 恢复异步身份复核', () {
    test('retrieveLostData 等待期间切号：恢复候选不发布', () async {
      final Harness harness = await Harness.setup();
      harness.sourceGateway.pickGate = Completer<void>();
      harness.sourceGateway.enqueuePick(
        AvatarPickOutcome.ready(harness.externalSourcePath),
      );
      final Future<AvatarCandidateStart> original = harness.repository
          .startCandidate(
            source: AvatarSource.camera,
            identity: harness.identityA,
          );
      await harness.sourceGateway.pickStarted.future;

      final DefaultAvatarRepository restarted = await harness.restart();
      harness.auth.loginAs(1);
      final AuthStateView current = harness.auth.view();
      harness.sourceGateway.lostResult = AvatarPickOutcome.ready(
        harness.externalSourcePath,
      );
      harness.sourceGateway.lostGate = Completer<void>();
      final Future<AvatarCandidateStart> recovering = restarted
          .consumeRecoveredOperation(
            identity: AvatarIdentity(
              userId: current.userId!,
              accountVersionKey: current.accountVersionKey!,
            ),
          );
      await harness.sourceGateway.lostStarted.future;
      harness.auth.loginAs(2);
      harness.sourceGateway.lostGate!.complete();

      expect(
        (await recovering).status,
        AvatarCandidateStartStatus.identityChanged,
      );
      expect(restarted.view().candidateReady, isFalse);
      harness.repository.discardCandidate();
      harness.sourceGateway.pickGate!.complete();
      await original;
    });
  });

  group('iOS 备份排除失败诊断', () {
    test('排除失败：initialize 记录脱敏诊断', () async {
      final List<String> diagnostics = <String>[];
      final Harness harness = await Harness.setup(
        diagnostic: diagnostics.add,
        backupExclusionSucceeds: false,
      );
      // avatarDirectory 在 initialize 中已执行。
      expect(harness.storage.backupExclusionFailed, isTrue);
      expect(
        diagnostics.where((String m) => m.contains('backup exclusion')),
        isNotEmpty,
      );
    });
  });
}
