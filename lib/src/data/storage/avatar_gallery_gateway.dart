import 'package:flutter/services.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';

/// 通过最小化的原生平台通道(Android MediaStore / iOS PhotoKit,
/// 仅新增写入)把头像字节交给系统相册的网关。
/// 不涉及任何第三方相册插件。
abstract interface class AvatarGalleryGateway {
  /// 把 [bytes] 写为名为 [fileName] 的新相册条目。绝不覆盖已有条目;
  /// 调用方提供带时间戳的唯一名称。
  Future<AvatarGallerySaveOutcome> savePng({
    required String fileName,
    required Uint8List bytes,
  });

  /// 在平台需要显式按目录标记时(iOS),把 [directoryPath] 标记为
  /// 排除在系统备份之外。Android 依赖 manifest 级的
  /// `allowBackup="false"`;原生侧在 Android 上将其
  /// 视为 no-op。无法应用排除标记时返回 false,
  /// 以便调用方记录诊断。
  Future<bool> excludeFromBackup(String directoryPath);
}

final class ChannelAvatarGalleryGateway implements AvatarGalleryGateway {
  ChannelAvatarGalleryGateway({MethodChannel? channel})
    : _channel = channel ?? MethodChannel(_channelName);

  static const String _channelName = 'dev.flutter.local.avatar_gallery';

  final MethodChannel _channel;

  @override
  Future<AvatarGallerySaveOutcome> savePng({
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final Object? result = await _channel.invokeMethod<Object>(
        'savePng',
        <String, Object?>{'fileName': fileName, 'bytes': bytes},
      );
      return _outcomeFromCode(result);
    } on PlatformException catch (error) {
      switch (error.code) {
        case 'permissionDenied':
          return AvatarGallerySaveOutcome.permissionDenied;
        case 'permissionPermanentlyDenied':
          return AvatarGallerySaveOutcome.permissionPermanentlyDenied;
        case 'insufficientSpace':
          return AvatarGallerySaveOutcome.insufficientSpace;
        default:
          return AvatarGallerySaveOutcome.failureWith(error);
      }
    } on MissingPluginException {
      // 测试和非移动端宿主从不配置该通道。
      return AvatarGallerySaveOutcome.failure;
    } on Object {
      return AvatarGallerySaveOutcome.failure;
    }
  }

  @override
  Future<bool> excludeFromBackup(String directoryPath) async {
    try {
      final Object? result = await _channel.invokeMethod<Object>(
        'excludeFromBackup',
        <String, Object>{'path': directoryPath},
      );
      return result == 'success';
    } on Object {
      // 尽力而为:目录标记失败不得阻塞流程,
      // 但要上报结果以便诊断。
      return false;
    }
  }

  AvatarGallerySaveOutcome _outcomeFromCode(Object? result) {
    if (result is! String) {
      return AvatarGallerySaveOutcome.failure;
    }
    switch (result) {
      case 'success':
        return AvatarGallerySaveOutcome.success;
      case 'permissionDenied':
        return AvatarGallerySaveOutcome.permissionDenied;
      case 'permissionPermanentlyDenied':
        return AvatarGallerySaveOutcome.permissionPermanentlyDenied;
      case 'insufficientSpace':
        return AvatarGallerySaveOutcome.insufficientSpace;
      default:
        return AvatarGallerySaveOutcome.failure;
    }
  }
}
