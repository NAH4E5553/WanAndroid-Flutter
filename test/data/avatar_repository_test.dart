import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/avatar_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_avatar_repository.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_file_storage.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';

import '../support/fake_avatar_dependencies.dart';

void main() {
  Future<AvatarImportedImage> imported(Harness h) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
    await File(h.externalSourcePath).writeAsBytes(bytes);
    return AvatarImportedImage(
      path: h.externalSourcePath,
      bytes: bytes.length,
      width: 1,
      height: 1,
    );
  }

  test('相册PNG导入复制为候选，不重复方向归一、不删租约源文件、不写pending', () async {
    final h = await Harness.setup();
    final image = await imported(h);
    final result = await h.repository.importCandidate(
      image: image,
      identity: h.identityA,
    );
    expect(result.status, AvatarCandidateStartStatus.ready);
    expect(result.candidatePath, isNot(image.path));
    expect(h.normalizationGateway.calls, 0);
    expect(File(image.path).existsSync(), true);
    expect(h.repository.hasPendingOperation(), false);
  });
  test('相册导入校验等待期间切号，迟到结果不能发布到新账号', () async {
    final h = await Harness.setup();
    final image = await imported(h);
    h.processor.ensureGate = Completer<void>();
    final pending = h.repository.importCandidate(
      image: image,
      identity: h.identityA,
    );
    await h.processor.ensureStarted.future;
    h.auth.loginAs(2);
    h.processor.ensureGate!.complete();
    expect((await pending).status, isNot(AvatarCandidateStartStatus.ready));
    expect(h.repository.view().candidateReady, false);
    expect(File(image.path).existsSync(), true);
  });
  test('相册导出描述与PNG头部不一致，不接纳候选', () async {
    final h = await Harness.setup();
    final image = await imported(h);
    final result = await h.repository.importCandidate(
      image: AvatarImportedImage(
        path: image.path,
        bytes: image.bytes,
        width: 2,
        height: 1,
      ),
      identity: h.identityA,
    );
    expect(result.status, AvatarCandidateStartStatus.failed);
    expect(h.repository.view().candidateReady, false);
  });

  test('取消候选后索引与当前头像不变，重启后仍为默认', () async {
    final Harness harness = await Harness.setup();
    await harness.repository.startCandidate(
      source: AvatarSource.gallery,
      identity: harness.identityA,
    );
    harness.repository.discardCandidate();

    expect(harness.repository.view().customAvailable, isFalse);
    final DefaultAvatarRepository restarted = await harness.restart();
    expect(restarted.view().customAvailable, isFalse);
  });

  test('提交成功后索引与文件落地，重启恢复同一头像', () async {
    final Harness harness = await Harness.setup();
    await harness.pickAndCommit();

    final AvatarStateView view = harness.repository.view();
    expect(view.customAvailable, isTrue);
    expect(File(view.customAvatarPath!).existsSync(), isTrue);

    final DefaultAvatarRepository restarted = await harness.restart();
    expect(restarted.view().customAvailable, isTrue);
    expect(restarted.view().customAvatarPath, view.customAvatarPath);
  });

  test('索引写失败：旧头像仍可用，重启不显示半成品', () async {
    final List<String> diagnostics = <String>[];
    final Harness harness = await Harness.setup(diagnostic: diagnostics.add);
    await harness.pickAndCommit();

    // 注入：下一次索引写入失败（磁盘满/IO 异常）。
    harness.storage.failIndexWrites = true;
    await harness.startCandidateReady();
    final AvatarCommitOutcome outcome = await harness.repository
        .commitCandidate(identity: harness.identityA, params: harness.params);
    // ignore: avoid_print
    print('DIAG: $diagnostics');
    expect(outcome.status, AvatarCommitStatus.storageFailed);
    // ignore: avoid_print
    print('DIAG: $diagnostics');

    final DefaultAvatarRepository restarted = await harness.restart();
    expect(restarted.view().customAvailable, isTrue);
    expect(restarted.view().customAvatarPath, harness.firstAvatarPath);
  });

  test('新文件写成功但索引未切换：重启显示旧头像，孤儿文件被清理', () async {
    final Harness harness = await Harness.setup();
    await harness.pickAndCommit();
    final String oldPath = harness.firstAvatarPath!;

    harness.storage.failIndexWrites = true;
    await harness.startCandidateReady();
    await harness.repository.commitCandidate(
      identity: harness.identityA,
      params: harness.params,
    );

    final DefaultAvatarRepository restarted = await harness.restart();
    expect(restarted.view().customAvatarPath, oldPath);
    // 新文件成为孤儿：重启后被清理，不残留。
    final List<String> avatarFiles = (await harness.storage.listAllFileNames())
        .where((String name) => name.endsWith('.png'))
        .toList();
    expect(avatarFiles.length, 1, reason: '只保留索引引用的旧头像文件');
  });

  test('索引切换后旧文件清理失败不影响新头像展示', () async {
    final Harness harness = await Harness.setup();
    await harness.pickAndCommit();
    final String newPath = harness.repository.view().customAvatarPath!;

    // 模拟旧文件清理失败：重新写入一个"旧文件名"的残留文件。
    final File stale = File(
      '${await harness.storage.avatarDirectory()}/orphan.png',
    );
    await stale.writeAsBytes(<int>[1, 2, 3]);

    final DefaultAvatarRepository restarted = await harness.restart();
    expect(restarted.view().customAvatarPath, newPath);
    // 孤儿在重启后被清理。
    expect(stale.existsSync(), isFalse);
  });

  test('A 选图期间退出并登录 B：A 的结果被拒绝，索引不变', () async {
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
    harness.auth.simulateLogout();
    harness.auth.loginAs(2);
    harness.sourceGateway.pickGate!.complete();
    final AvatarCandidateStart result = await pending;

    expect(result.status, AvatarCandidateStartStatus.identityChanged);
    expect(harness.repository.view().customAvailable, isFalse);
    expect(harness.repository.view().candidateReady, isFalse);
  });

  test('A 退出后重新登录 A：旧进程内操作身份失效仍被拒绝', () async {
    final Harness harness = await Harness.setup();
    harness.auth.loginAs(1);
    // 重新登录 A：accountVersionKey 递增，旧 identity 立即失效。
    harness.auth.loginAs(1);

    final AvatarCommitOutcome outcome = await harness.repository
        .commitCandidate(
          identity: const AvatarIdentity(
            userId: 1,
            accountVersionKey: 'instance:1',
          ),
          params: harness.params,
        );
    expect(outcome.status, AvatarCommitStatus.identityChanged);
  });

  test('Android lost data：pending 与已验证 userId 匹配才恢复到候选', () async {
    final Harness harness = await Harness.setup();
    // 模拟进程在外部页期间被杀：pending 已持久化，pick 未来不会返回。
    harness.sourceGateway.pickGate = Completer<void>();
    harness.sourceGateway.enqueuePick(
      AvatarPickOutcome.ready(harness.externalSourcePath),
    );
    final Future<AvatarCandidateStart> ignored = harness.repository
        .startCandidate(
          source: AvatarSource.camera,
          identity: harness.identityA,
        );
    unawaited(ignored);
    // 等待外部页真正打开（此时 pending 已持久化）。
    await harness.sourceGateway.pickStarted.future;

    // 进程重启：新仓储实例读取同一持久化目录。
    final DefaultAvatarRepository restarted = await harness.restart();
    // ignore: avoid_print
    print(
      'PENDING-FILE: ${await harness.storage.pendingFilePath()} exists=${await harness.storage.fileExists(await harness.storage.pendingFilePath())}',
    );
    // ignore: avoid_print
    print('HAS-PENDING: ${restarted.hasPendingOperation()}');
    expect(restarted.hasPendingOperation(), isTrue);

    // 会话恢复完成后：同一 userId 重新验证 → 恢复候选。
    harness.auth.loginAs(1);
    final AuthStateView recoveredSession = harness.auth.view();
    harness.sourceGateway.lostResult = AvatarPickOutcome.ready(
      harness.externalSourcePath,
    );
    final AvatarCandidateStart recovered = await restarted
        .consumeRecoveredOperation(
          identity: AvatarIdentity(
            userId: recoveredSession.userId!,
            accountVersionKey: recoveredSession.accountVersionKey!,
          ),
        );
    expect(recovered.status, AvatarCandidateStartStatus.ready);
    expect(restarted.view().candidateReady, isTrue);
    ignored.ignore();
  });

  test('pending 缺失、账号不匹配或超时：清理结果且不改头像', () async {
    final Harness harness = await Harness.setup();

    // pending 缺失。
    final DefaultAvatarRepository fresh = await harness.restart();
    expect(fresh.hasPendingOperation(), isFalse);
    expect(
      (await fresh.consumeRecoveredOperation(identity: harness.identityA))
          .status,
      AvatarCandidateStartStatus.cancelled,
    );

    // 账号不匹配：pending 属于 user 1，恢复时登录的是 user 2。
    final Harness pendingHarness = await Harness.setupWithPending(
      userId: 1,
      age: const Duration(hours: 1),
    );
    pendingHarness.auth.loginAs(2);
    final AvatarCandidateStart mismatched = await pendingHarness.repository
        .consumeRecoveredOperation(
          identity: const AvatarIdentity(
            userId: 2,
            accountVersionKey: 'instance:1',
          ),
        );
    expect(mismatched.status, AvatarCandidateStartStatus.cancelled);
    expect(pendingHarness.repository.view().customAvailable, isFalse);

    // 超时：pending 已超过 24 小时。
    final Harness timedOut = await Harness.setupWithPending(
      userId: 1,
      age: const Duration(hours: 25),
    );
    timedOut.auth.loginAs(1);
    final AvatarCandidateStart expired = await timedOut.repository
        .consumeRecoveredOperation(
          identity: const AvatarIdentity(
            userId: 1,
            accountVersionKey: 'instance:1',
          ),
        );
    expect(expired.status, AvatarCandidateStartStatus.cancelled);
  });

  test('游客态（无已验证身份）：恢复直接清理 pending', () async {
    final Harness harness = await Harness.setupWithPending(
      userId: 1,
      age: const Duration(hours: 1),
    );
    // 保持游客（未登录）。
    final AvatarCandidateStart result = await harness.repository
        .consumeRecoveredOperation(identity: null);
    expect(result.status, AvatarCandidateStartStatus.cancelled);
  });

  test('同一账号重登恢复头像，不同账号相互隔离', () async {
    final Harness harness = await Harness.setup();
    await harness.pickAndCommit();
    final String avatarPath = harness.repository.view().customAvatarPath!;

    harness.auth.simulateLogout();
    expect(harness.repository.view().customAvailable, isFalse);

    harness.auth.loginAs(1);
    expect(harness.repository.view().customAvailable, isTrue);
    expect(harness.repository.view().customAvatarPath, avatarPath);

    harness.auth.loginAs(2);
    expect(harness.repository.view().customAvailable, isFalse);

    harness.auth.loginAs(1);
    expect(harness.repository.view().customAvatarPath, avatarPath);
  });

  test('保存到相册单飞：进行中的重复触发不会重复写入', () async {
    final Harness harness = await Harness.setup();
    await harness.pickAndCommit();
    harness.galleryGateway.delay = const Duration(milliseconds: 50);
    harness.galleryGateway.enqueue(AvatarGallerySaveOutcome.success);

    final Future<AvatarGallerySaveOutcome> first = harness.repository
        .saveCurrentToGallery(identity: harness.identityA);
    final AvatarGallerySaveOutcome second = await harness.repository
        .saveCurrentToGallery(identity: harness.identityA);
    final AvatarGallerySaveOutcome firstOutcome = await first;

    expect(firstOutcome.status, AvatarGallerySaveStatus.success);
    // 第二次被单飞守卫拒绝（忽略），网关只写一次。
    expect(harness.galleryGateway.savedFileNames.length, 1);
    expect(second.status, AvatarGallerySaveStatus.failure);
  });

  test('默认头像保存使用页面渲染的 PNG；自定义头像保存已生效文件', () async {
    final Harness harness = await Harness.setup();
    bool rendererCalled = false;
    final AvatarGallerySaveOutcome defaultOutcome = await harness.repository
        .saveCurrentToGallery(
          identity: harness.identityA,
          defaultAvatarPng: () async {
            rendererCalled = true;
            return <int>[1, 2, 3];
          },
        );
    expect(defaultOutcome.status, AvatarGallerySaveStatus.success);
    expect(rendererCalled, isTrue);

    await harness.pickAndCommit();
    bool rendererCalledAgain = false;
    await harness.repository.saveCurrentToGallery(
      identity: harness.identityA,
      defaultAvatarPng: () async {
        rendererCalledAgain = true;
        return <int>[9];
      },
    );
    expect(rendererCalledAgain, isFalse);
  });

  test('存储读取失败（索引损坏）：回退默认头像并保留诊断', () async {
    final Harness harness = await Harness.setup();
    await harness.pickAndCommit();
    // 模拟索引损坏：写入非法 JSON。
    await File(await harness.storage.indexFilePath())
        .writeAsString('{not-json');
    final List<String> diagnostics = <String>[];
    final DefaultAvatarRepository restarted = await harness.restart(
      diagnostic: diagnostics.add,
    );
    expect(restarted.view().customAvailable, isFalse);
    expect(diagnostics, isNotEmpty);
  });
}

class Harness {
  Harness._(
    this.storage,
    this.auth,
    this.sourceGateway,
    this.galleryGateway,
    this.normalizationGateway,
    this.processor,
    this.repository,
    this.externalSourcePath,
  );

  static Future<Harness> setup({
    void Function(String)? diagnostic,
    bool backupExclusionSucceeds = true,
  }) async {
    final Harness harness = Harness._create(
      diagnostic: diagnostic,
      backupExclusionSucceeds: backupExclusionSucceeds,
    );
    await harness.repository.initialize();
    harness.auth.loginAs(1);
    return harness;
  }

  /// 生成一个已持久化 pending 的启动现场（模拟进程在外部页期间被杀）。
  static Future<Harness> setupWithPending({
    required int userId,
    required Duration age,
  }) async {
    final Harness harness = Harness._create();
    await harness.repository.initialize();
    harness.auth.loginAs(userId);
    await harness.storage.writePendingOperation(
      PendingAvatarOperation(
        operationId: 'op_pending',
        userId: userId,
        source: AvatarSource.camera,
        createdAt: harness.now().subtract(age),
      ),
    );
    return harness;
  }

  static Harness _create({
    void Function(String)? diagnostic,
    bool backupExclusionSucceeds = true,
  }) {
    final List<String> diagLog = <String>[];
    final AvatarTestAuthRepository auth = AvatarTestAuthRepository();
    final FakeAvatarImageSourceGateway sourceGateway =
        FakeAvatarImageSourceGateway();
    final FakeAvatarGalleryGateway galleryGateway = FakeAvatarGalleryGateway();
    final FakeAvatarImageNormalizationGateway normalizationGateway =
        FakeAvatarImageNormalizationGateway();
    final FakeAvatarImageProcessor processor = FakeAvatarImageProcessor();
    final AvatarFileStorage storage = AvatarFileStorage(
      directories: TempAvatarDirectories(),
      excludeFromBackup: (String directory) async {
        galleryGateway.excludedDirectories.add(directory);
        return backupExclusionSucceeds;
      },
    );
    DateTime now() => DateTime.now();
    final DefaultAvatarRepository repository = DefaultAvatarRepository(
      authRepository: auth,
      sourceGateway: sourceGateway,
      galleryGateway: galleryGateway,
      normalizationGateway: normalizationGateway,
      processor: processor,
      storage: storage,
      now: now,
      diagnostic: diagnostic ?? diagLog.add,
    );
    final Directory external = Directory.systemTemp.createTempSync(
      'avatar_external',
    );
    final File source = File('${external.path}/picked.jpg');
    source.writeAsBytesSync(<int>[1, 2, 3, 4]);
    final Harness harness = Harness._(
      storage,
      auth,
      sourceGateway,
      galleryGateway,
      normalizationGateway,
      processor,
      repository,
      source.path,
    );
    harness.diagLog = diagLog;
    return harness;
  }

  final AvatarFileStorage storage;
  final AvatarTestAuthRepository auth;
  late List<String> diagLog = <String>[];
  final FakeAvatarImageSourceGateway sourceGateway;
  final FakeAvatarGalleryGateway galleryGateway;
  final FakeAvatarImageNormalizationGateway normalizationGateway;
  final FakeAvatarImageProcessor processor;
  final DefaultAvatarRepository repository;
  final String externalSourcePath;

  final AvatarIdentity identityA = const AvatarIdentity(
    userId: 1,
    accountVersionKey: 'instance:1',
  );
  final AvatarCropParams params = const AvatarCropParams(
    scale: 1,
    rotationRadians: 0,
    offsetX: 0,
    offsetY: 0,
  );
  String? firstAvatarPath;
  DateTime Function() now = () => DateTime.now();

  /// 完整走一遍"选图 → 提交"，并记录首个成功头像路径。
  Future<void> pickAndCommit() async {
    await startCandidateReady();
    final AvatarCommitOutcome outcome = await repository.commitCandidate(
      identity: identityA,
      params: params,
    );
    if (outcome.status != AvatarCommitStatus.committed) {
      // ignore: avoid_print
      print('PICKCOMMIT-DIAG: $diagLog');
    }
    expect(outcome.status, AvatarCommitStatus.committed);
    firstAvatarPath ??= repository.view().customAvatarPath;
  }

  /// 注入一张真实存在的"系统返回文件"并完成选图。
  /// 系统返回的临时文件在候选复制后即被清理，因此每次注入都重建源文件。
  Future<void> startCandidateReady() async {
    final File source = File(externalSourcePath);
    if (!source.existsSync()) {
      source.writeAsBytesSync(<int>[1, 2, 3, 4]);
    }
    sourceGateway.enqueuePick(AvatarPickOutcome.ready(externalSourcePath));
    final AvatarCandidateStart result = await repository.startCandidate(
      source: AvatarSource.gallery,
      identity: identityA,
    );
    expect(result.status, AvatarCandidateStartStatus.ready);
  }

  /// 模拟进程重启：同一持久化目录上的新仓储实例。
  Future<DefaultAvatarRepository> restart({
    void Function(String message)? diagnostic,
  }) async {
    final DefaultAvatarRepository restarted = DefaultAvatarRepository(
      authRepository: auth,
      sourceGateway: sourceGateway,
      galleryGateway: galleryGateway,
      normalizationGateway: normalizationGateway,
      processor: FakeAvatarImageProcessor(),
      storage: storage,
      diagnostic: diagnostic,
    );
    await restarted.initialize();
    return restarted;
  }
}

extension on Future<AvatarCandidateStart> {
  void ignore() {}
}
