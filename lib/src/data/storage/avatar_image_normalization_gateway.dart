import 'dart:io';

import 'package:flutter/services.dart';

/// 在候选图被展示或裁剪之前,应用编码图像 EXIF 方向的
/// 原生边界。原生实现还会在分配全尺寸位图之前,
/// 强制执行相同的解码限制。
abstract interface class AvatarImageNormalizationGateway {
  Future<void> normalizeToPng({
    required String sourcePath,
    required String destinationPath,
    required int maxDimension,
    required int maxPixelCount,
    required int maxFileBytes,
  });
}

final class AvatarNormalizationException implements Exception {
  const AvatarNormalizationException(this.reason);

  final String reason;

  @override
  String toString() => 'AvatarNormalizationException($reason)';
}

final class ChannelAvatarImageNormalizationGateway
    implements AvatarImageNormalizationGateway {
  const ChannelAvatarImageNormalizationGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'dev.flutter.local.avatar_image';

  final MethodChannel _channel;

  @override
  Future<void> normalizeToPng({
    required String sourcePath,
    required String destinationPath,
    required int maxDimension,
    required int maxPixelCount,
    required int maxFileBytes,
  }) async {
    try {
      final Object? result = await _channel.invokeMethod<Object>(
        'normalizeToPng',
        <String, Object>{
          'sourcePath': sourcePath,
          'destinationPath': destinationPath,
          'maxDimension': maxDimension,
          'maxPixelCount': maxPixelCount,
          'maxFileBytes': maxFileBytes,
        },
      );
      if (result == 'success') {
        return;
      }
      throw AvatarNormalizationException(
        result == 'rejected' ? 'source-rejected' : 'normalization-failed',
      );
    } on AvatarNormalizationException {
      rethrow;
    } on PlatformException catch (error) {
      throw AvatarNormalizationException(error.code);
    } on MissingPluginException {
      throw const AvatarNormalizationException('plugin-missing');
    } on Object {
      throw const AvatarNormalizationException('normalization-failed');
    }
  }
}

/// 仅用于测试/本地宿主的实现。生产组装必须使用原生网关,
/// 因为字节复制不会应用 EXIF 方向。
final class CopyingAvatarImageNormalizationGateway
    implements AvatarImageNormalizationGateway {
  const CopyingAvatarImageNormalizationGateway();

  @override
  Future<void> normalizeToPng({
    required String sourcePath,
    required String destinationPath,
    required int maxDimension,
    required int maxPixelCount,
    required int maxFileBytes,
  }) async {
    await File(sourcePath).copy(destinationPath);
  }
}
