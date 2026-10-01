import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/avatar_repository.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_file_storage.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_gallery_gateway.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_image_normalization_gateway.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_image_processor.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_image_source_gateway.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';

/// 可脚本化的认证仓储假体：直接操纵 AuthStateView 并通知监听者。
/// accountVersionKey 在每次 `loginAs` 时递增，模拟"重新登录即新操作身份"。
final class AvatarTestAuthRepository implements AuthRepository {
  AvatarTestAuthRepository({AuthStateView? initialView})
    : _view =
          initialView ??
          const AuthStateView(
            loading: false,
            authenticated: false,
            unverified: false,
            expiredNotice: false,
            storageNotice: false,
            displayName: null,
          );

  AuthStateView _view;
  int _versionCounter = 0;
  final List<void Function()> _listeners = <void Function()>[];

  @override
  void addListener(void Function() listener) => _listeners.add(listener);

  @override
  void removeListener(void Function() listener) => _listeners.remove(listener);

  @override
  AuthStateView view() => _view;

  void emit(AuthStateView view) {
    _view = view;
    for (final void Function() listener in List.of(_listeners)) {
      listener();
    }
  }

  /// 模拟已验证登录 A（再次调用模拟退出后重新登录，versionKey 递增）。
  void loginAs(int userId) {
    _versionCounter += 1;
    emit(
      AuthStateView(
        loading: false,
        authenticated: true,
        unverified: false,
        expiredNotice: false,
        storageNotice: false,
        displayName: 'user$userId',
        userId: userId,
        accountVersionKey: 'instance:$_versionCounter',
      ),
    );
  }

  /// 模拟退出（接口方法的 Fake 版本在下方）。
  void simulateLogout() {
    emit(
      AuthStateView(
        loading: false,
        authenticated: false,
        unverified: false,
        expiredNotice: false,
        storageNotice: false,
        displayName: null,
      ),
    );
  }

  @override
  Future<DataResult<void>> restore() async => const DataSuccess<void>(null);

  @override
  Future<DataResult<void>> login(
    String username,
    String password, {
    RequestCancellation cancellation = const LiveRequestCancellation(),
  }) async => const DataSuccess<void>(null);

  @override
  Future<LogoutOutcome> logout() async =>
      LogoutOutcome(generation: 1, remote: const DataSuccess<void>(null));
}

/// 可脚本化的选图网关假体：pick 结果按队列消费，支持延迟（模拟外部页期间
/// 的会话变化）与一次性 lost data。
final class FakeAvatarImageSourceGateway implements AvatarImageSourceGateway {
  final List<AvatarPickOutcome> pickResults = <AvatarPickOutcome>[];
  final List<Duration> pickDelays = <Duration>[];

  /// 非空时 pick 会等待该闸门，模拟"外部页打开期间发生其他事"。
  Completer<void>? pickGate;
  Completer<void>? lostGate;

  /// pick 被调用即完成，用于测试同步等待"pending 已写盘"。
  final Completer<void> pickStarted = Completer<void>();
  final Completer<void> lostStarted = Completer<void>();
  AvatarPickOutcome? lostResult;
  int pickCalls = 0;
  int lostCalls = 0;

  void enqueuePick(
    AvatarPickOutcome outcome, {
    Duration delay = Duration.zero,
  }) {
    pickResults.add(outcome);
    pickDelays.add(delay);
  }

  @override
  Future<AvatarPickOutcome> pick({required AvatarSource source}) async {
    pickCalls += 1;
    if (!pickStarted.isCompleted) {
      pickStarted.complete();
    }
    final Completer<void>? gate = pickGate;
    if (gate != null) {
      await gate.future;
    }
    if (pickResults.isEmpty) {
      return AvatarPickOutcome.cancelled;
    }
    final Duration delay = pickDelays.removeAt(0);
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return pickResults.removeAt(0);
  }

  @override
  Future<AvatarPickOutcome> retrieveLostData() async {
    lostCalls += 1;
    if (!lostStarted.isCompleted) {
      lostStarted.complete();
    }
    final Completer<void>? gate = lostGate;
    if (gate != null) {
      await gate.future;
    }
    return lostResult ?? AvatarPickOutcome.cancelled;
  }
}

/// 可脚本化的处理器假体：renderCrop 返回真实 PNG 字节（默认 512×512），
/// validate/canDecode 可按需注入失败。
final class FakeAvatarImageProcessor implements AvatarImageProcessor {
  FakeAvatarImageProcessor({this.pngBytes, this.decodeFails = false});

  List<int>? pngBytes;
  bool decodeFails;
  bool validateResult = true;
  bool canDecodeResult = true;
  bool oversized = false;
  Completer<void>? ensureGate;
  final Completer<void> ensureStarted = Completer<void>();
  Duration renderDelay = Duration.zero;
  int renderCalls = 0;
  AvatarCropParams? lastParams;
  String? lastSourcePath;

  @override
  Future<Uint8List> renderCrop({
    required String sourcePath,
    required AvatarCropParams params,
  }) async {
    renderCalls += 1;
    lastParams = params;
    lastSourcePath = sourcePath;
    if (renderDelay > Duration.zero) {
      await Future<void>.delayed(renderDelay);
    }
    if (decodeFails) {
      throw const AvatarDecodeException('injected');
    }
    return Uint8List.fromList(pngBytes ?? await renderSolidPng());
  }

  @override
  Future<void> ensureDecodable({
    required String path,
    required int maxDimension,
    required int maxPixelCount,
    required int maxFileBytes,
  }) async {
    if (!ensureStarted.isCompleted) {
      ensureStarted.complete();
    }
    final Completer<void>? gate = ensureGate;
    if (gate != null) {
      await gate.future;
    }
    if (decodeFails) {
      throw const AvatarDecodeException('decode-failed');
    }
    if (oversized) {
      throw const AvatarDecodeException('oversized');
    }
  }

  @override
  Future<bool> canDecode(String path) async => canDecodeResult;

  @override
  Future<bool> validateImage({
    required String path,
    required int width,
    required int height,
  }) async => validateResult;
}

/// Native EXIF normalization seam used by repository tests. It copies the
/// fixture while exposing a gate so account changes can be injected during
/// the asynchronous normalization window.
final class FakeAvatarImageNormalizationGateway
    implements AvatarImageNormalizationGateway {
  Completer<void>? gate;
  final Completer<void> started = Completer<void>();
  bool fail = false;
  int calls = 0;

  @override
  Future<void> normalizeToPng({
    required String sourcePath,
    required String destinationPath,
    required int maxDimension,
    required int maxPixelCount,
    required int maxFileBytes,
  }) async {
    calls += 1;
    if (!started.isCompleted) {
      started.complete();
    }
    final Completer<void>? currentGate = gate;
    if (currentGate != null) {
      await currentGate.future;
    }
    if (fail) {
      throw const AvatarNormalizationException('injected');
    }
    await File(sourcePath).copy(destinationPath);
  }
}

/// 可脚本化的相册写入网关假体：记录调用并支持慢速写入（单飞验证）。
final class FakeAvatarGalleryGateway implements AvatarGalleryGateway {
  final List<AvatarGallerySaveOutcome> results = <AvatarGallerySaveOutcome>[];
  final List<Duration> delays = <Duration>[];
  final List<String> savedFileNames = <String>[];
  final List<String> excludedDirectories = <String>[];
  Duration delay = Duration.zero;

  void enqueue(
    AvatarGallerySaveOutcome outcome, {
    Duration delay = Duration.zero,
  }) {
    results.add(outcome);
    delays.add(delay);
  }

  @override
  Future<AvatarGallerySaveOutcome> savePng({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    savedFileNames.add(fileName);
    if (results.isEmpty) {
      return AvatarGallerySaveOutcome.success;
    }
    return results.removeAt(0);
  }

  @override
  Future<bool> excludeFromBackup(String directoryPath) async {
    excludedDirectories.add(directoryPath);
    return true;
  }
}

/// 一次性临时目录（真实文件 IO，非内存模拟）；每次实例化独立目录组。
final class TempAvatarDirectories implements AvatarDirectories {
  Directory? _support;
  Directory? _temp;

  @override
  Future<String> applicationSupportDirectory() async =>
      (await _ensureSupport()).path;

  @override
  Future<String> temporaryDirectory() async => (await _ensureTemp()).path;

  Future<Directory> _ensureSupport() async {
    final Directory existing = _support ??= await Directory.systemTemp
        .createTemp('avatar_support');
    return existing;
  }

  Future<Directory> _ensureTemp() async {
    final Directory existing = _temp ??= await Directory.systemTemp.createTemp(
      'avatar_temp',
    );
    return existing;
  }
}

/// 生成一张真实的 PNG 字节（dart:ui 编码），供提交管线与默认头像渲染。
Future<Uint8List> renderSolidPng({
  int width = 512,
  int height = 512,
  ui.Color color = const ui.Color(0xFF3366CC),
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = color,
  );
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(width, height);
  final ByteData? bytes = await image.toByteData(
    format: ui.ImageByteFormat.png,
  );
  image.dispose();
  return bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
}

/// 可状态操纵的头像仓储假体：Widget/ViewModel 测试直接改字段并通知。
class FakeAvatarRepository extends ChangeNotifier implements AvatarRepository {
  FakeAvatarRepository({AvatarStateView? initialView})
    : _view =
          initialView ??
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
          );

  @override
  Future<AvatarCandidateStart> importCandidate({
    required AvatarImportedImage image,
    required AvatarIdentity identity,
  }) async => const AvatarCandidateStart.failed();

  AvatarStateView _view;
  AvatarGallerySaveStatus nextSaveStatus = AvatarGallerySaveStatus.success;
  int saveCalls = 0;
  int discardCalls = 0;
  bool notifyOnDiscard = false;

  void emit(AvatarStateView view) {
    _view = view;
    notifyListeners();
  }

  @override
  AvatarStateView view() => _view;

  @override
  Future<AvatarCandidateStart> startCandidate({
    required AvatarSource source,
    required AvatarIdentity identity,
  }) async => const AvatarCandidateStart.cancelled();

  @override
  Future<AvatarCommitOutcome> commitCandidate({
    required AvatarIdentity identity,
    required AvatarCropParams params,
  }) async => AvatarCommitOutcome.committed;

  @override
  void discardCandidate() {
    discardCalls += 1;
    if (notifyOnDiscard) {
      notifyListeners();
    }
  }

  @override
  Future<AvatarGallerySaveOutcome> saveCurrentToGallery({
    required AvatarIdentity identity,
    Future<List<int>?> Function()? defaultAvatarPng,
  }) async {
    saveCalls += 1;
    return AvatarGallerySaveOutcome.of(nextSaveStatus);
  }

  @override
  bool hasPendingOperation() => false;

  @override
  void markRecoveryConsumed() {}

  @override
  Future<AvatarCandidateStart> consumeRecoveredOperation({
    required AvatarIdentity? identity,
  }) async => const AvatarCandidateStart.cancelled();
}
