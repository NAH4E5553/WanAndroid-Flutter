import 'dart:io';

import 'package:flutter/services.dart';

/// Native boundary that applies the encoded image's EXIF orientation before
/// the candidate is ever shown or cropped. The native implementations also
/// enforce the same decode limits before allocating a full-size bitmap.
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

/// Test-only/local-host implementation. Production composition must use the
/// native gateway because a byte copy does not apply EXIF orientation.
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
