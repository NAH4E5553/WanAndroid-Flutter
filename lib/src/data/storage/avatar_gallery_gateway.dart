import 'package:flutter/services.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';

/// Gateway that hands avatar bytes to the system gallery through the minimal
/// native platform channel (Android MediaStore / iOS PhotoKit add-only).
/// No third-party gallery plugin is involved.
abstract interface class AvatarGalleryGateway {
  /// Writes [bytes] as a new gallery entry named [fileName]. Never overwrites
  /// existing entries; the caller supplies unique time-stamped names.
  Future<AvatarGallerySaveOutcome> savePng({
    required String fileName,
    required Uint8List bytes,
  });

  /// Marks [directoryPath] as excluded from system backups where the
  /// platform needs an explicit per-directory flag (iOS). Android relies on
  /// the manifest-level `allowBackup="false"`; the native side treats this
  /// as a no-op there. Returns false when the exclusion could not be applied
  /// so the caller can record a diagnostic.
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
      // Tests and non-mobile hosts never configure the channel.
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
      // Best effort: failure to flag the directory must not block the flow,
      // but the outcome is reported so it can be diagnosed.
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
