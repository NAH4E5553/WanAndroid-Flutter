import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:wanandroid_flutter/src/model/avatar.dart';

/// Thrown when the source image cannot be decoded or exceeds the supported
/// dimensions. Never carries path or file contents in [message].
final class AvatarDecodeException implements Exception {
  const AvatarDecodeException(this.reason);

  final String reason;

  @override
  String toString() => 'AvatarDecodeException($reason)';
}

/// Image pipeline for the local avatar, isolated at the data/platform
/// boundary so neither the feature layers nor the repository contract see
/// `dart:ui` types.
///
/// Transform contract shared with the adjust screen (both sides must use the
/// same composition so the preview equals the committed output):
/// - the crop window is an axis-aligned 512×512 square;
/// - `AvatarCropParams.scale` is relative to the cover-fit scale, i.e. the
///   scale at which the decoded image fully covers the axis-aligned window;
/// - the image center is drawn at `window center + offset * window side`;
/// - `rotationRadians` rotates around the image center.
abstract interface class AvatarImageProcessor {
  /// Decodes [sourcePath], renders the user transform into the 512×512 crop
  /// and returns PNG-encoded bytes. Throws [AvatarDecodeException] when the
  /// source cannot be decoded or exceeds [maxSourceDimension].
  Future<Uint8List> renderCrop({
    required String sourcePath,
    required AvatarCropParams params,
  });

  /// Cheap header-level validation for a freshly picked candidate: the file
  /// must decode and must not exceed [maxDimension] on either side, so a
  /// corrupt or hostile image never reaches the adjust page or triggers a
  /// full-size decode. Throws [AvatarDecodeException].
  Future<void> ensureDecodable({
    required String path,
    required int maxDimension,
    required int maxPixelCount,
    required int maxFileBytes,
  });

  /// Whether [path] decodes successfully at all.
  Future<bool> canDecode(String path);

  /// Whether [path] decodes to an image of exactly [width]×[height].
  Future<bool> validateImage({
    required String path,
    required int width,
    required int height,
  });
}

final class UiAvatarImageProcessor implements AvatarImageProcessor {
  const UiAvatarImageProcessor();

  /// Sources above this size are rejected as "oversized" before a full
  /// decode, so a hostile or accidental huge image cannot blow up the app.
  static const int maxSourceDimension = 8192;
  static const int maxSourcePixelCount = 16000000;
  static const int maxSourceFileBytes = 32 * 1024 * 1024;
  static const int outputSize = 512;

  @override
  Future<void> ensureDecodable({
    required String path,
    required int maxDimension,
    required int maxPixelCount,
    required int maxFileBytes,
  }) async {
    try {
      final File source = File(path);
      final int fileBytes = await source.length();
      if (fileBytes <= 0 || fileBytes > maxFileBytes) {
        throw const AvatarDecodeException('oversized');
      }
      final Uint8List raw = await source.readAsBytes();
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
        raw,
      );
      final ui.ImageDescriptor descriptor;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
      } on Object {
        throw const AvatarDecodeException('decode-failed');
      } finally {
        buffer.dispose();
      }
      try {
        if (descriptor.width > maxDimension ||
            descriptor.height > maxDimension ||
            descriptor.width * descriptor.height > maxPixelCount) {
          throw const AvatarDecodeException('oversized');
        }
      } finally {
        descriptor.dispose();
      }
    } on AvatarDecodeException {
      rethrow;
    } on Object {
      throw const AvatarDecodeException('decode-failed');
    }
  }

  @override
  Future<Uint8List> renderCrop({
    required String sourcePath,
    required AvatarCropParams params,
  }) async {
    await ensureDecodable(
      path: sourcePath,
      maxDimension: maxSourceDimension,
      maxPixelCount: maxSourcePixelCount,
      maxFileBytes: maxSourceFileBytes,
    );
    final Uint8List raw = await File(sourcePath).readAsBytes();
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      raw,
    );
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
      } on Object {
        throw const AvatarDecodeException('decode-failed');
      }
      if (descriptor.width > maxSourceDimension ||
          descriptor.height > maxSourceDimension ||
          descriptor.width * descriptor.height > maxSourcePixelCount) {
        throw const AvatarDecodeException('oversized');
      }
      codec = await descriptor.instantiateCodec();
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image image = frame.image;
      final double coverScale =
          outputSize / image.width > outputSize / image.height
          ? outputSize / image.width
          : outputSize / image.height;
      final double scale = coverScale * params.scale;
      ui.Picture? picture;
      ui.Image? rendered;
      try {
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        final ui.Canvas canvas = ui.Canvas(recorder);
        // Opaque-free: the crop area outside the transformed image stays
        // transparent, which the min-scale clamp on the adjust screen makes
        // unreachable for valid inputs.
        canvas.translate(
          outputSize / 2 + params.offsetX * outputSize,
          outputSize / 2 + params.offsetY * outputSize,
        );
        canvas.rotate(params.rotationRadians);
        canvas.scale(scale);
        canvas.drawImage(
          image,
          ui.Offset(-image.width / 2, -image.height / 2),
          ui.Paint(),
        );
        picture = recorder.endRecording();
        rendered = await picture.toImage(outputSize, outputSize);
        final ByteData? bytes = await rendered.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (bytes == null) {
          throw const AvatarDecodeException('encode-failed');
        }
        return bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
      } finally {
        picture?.dispose();
        rendered?.dispose();
      }
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  @override
  Future<bool> canDecode(String path) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      final Uint8List raw = await File(path).readAsBytes();
      buffer = await ui.ImmutableBuffer.fromUint8List(raw);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      codec = await descriptor.instantiateCodec();
      final ui.FrameInfo frame = await codec.getNextFrame();
      frame.image.dispose();
      return true;
    } on Object {
      return false;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  @override
  Future<bool> validateImage({
    required String path,
    required int width,
    required int height,
  }) async {
    try {
      final Uint8List raw = await File(path).readAsBytes();
      const List<int> pngSignature = <int>[0x89, 0x50, 0x4E, 0x47];
      for (int i = 0; i < pngSignature.length; i++) {
        if (raw.length <= i || raw[i] != pngSignature[i]) {
          return false;
        }
      }
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
        raw,
      );
      ui.ImageDescriptor? descriptor;
      ui.Codec? codec;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width != width || descriptor.height != height) {
          return false;
        }
        codec = await descriptor.instantiateCodec();
        final ui.FrameInfo frame = await codec.getNextFrame();
        frame.image.dispose();
        return true;
      } finally {
        codec?.dispose();
        descriptor?.dispose();
        buffer.dispose();
      }
    } on Object {
      return false;
    }
  }
}
