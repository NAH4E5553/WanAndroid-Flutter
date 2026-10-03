import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:wanandroid_flutter/src/model/avatar.dart';

/// 源图像无法解码或超出受支持尺寸时抛出。[message] 中绝不携带
/// 路径或文件内容。
final class AvatarDecodeException implements Exception {
  const AvatarDecodeException(this.reason);

  final String reason;

  @override
  String toString() => 'AvatarDecodeException($reason)';
}

/// 本地头像的图像处理管线,隔离在数据/平台边界,使 Feature 层
/// 和 Repository 契约都看不到
/// `dart:ui` 类型。
///
/// 与调整页面共享的变换契约(双方必须使用相同的合成方式,
/// 保证预览与提交输出一致):
/// - 裁剪窗口是轴对齐的 512×512 正方形;
/// - `AvatarCropParams.scale` 相对于 cover-fit scale,即解码图像
///   完全覆盖轴对齐窗口时的 scale;
/// - 图像中心绘制在 `window center + offset * window side`;
/// - `rotationRadians` 绕图像中心旋转。
abstract interface class AvatarImageProcessor {
  /// 解码 [sourcePath],把用户变换渲染进 512×512 裁剪结果,
  /// 返回 PNG 编码字节。源无法解码或超出 [maxSourceDimension] 时
  /// 抛出 [AvatarDecodeException]。
  Future<Uint8List> renderCrop({
    required String sourcePath,
    required AvatarCropParams params,
  });

  /// 对新挑选候选图的廉价头部级校验:文件必须能解码,且任一边
  /// 不得超过 [maxDimension],使损坏或恶意图像永远到不了
  /// 调整页面,也不会触发
  /// 全尺寸解码。抛出 [AvatarDecodeException]。
  Future<void> ensureDecodable({
    required String path,
    required int maxDimension,
    required int maxPixelCount,
    required int maxFileBytes,
  });

  /// [path] 是否能成功解码。
  Future<bool> canDecode(String path);

  /// [path] 是否解码为恰好 [width]×[height] 的图像。
  Future<bool> validateImage({
    required String path,
    required int width,
    required int height,
  });
}

final class UiAvatarImageProcessor implements AvatarImageProcessor {
  const UiAvatarImageProcessor();

  /// 超过此尺寸的源在全尺寸解码前即按 "oversized" 拒绝,
  /// 使恶意或意外超大的图像无法拖垮应用。
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
        // 不填充不透明背景:变换后图像之外的裁剪区域
        // 保持透明,调整页面的最小 scale 钳制保证
        // 合法输入不会触及该区域。
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
