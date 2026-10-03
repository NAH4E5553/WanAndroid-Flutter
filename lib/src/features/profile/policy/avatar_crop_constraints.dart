import 'dart:math' as math;

import 'package:wanandroid_flutter/src/model/avatar.dart';

/// 调整 UI 与其回归测试共享的纯裁剪几何。
/// 把它放在 Widget 之外,防止测试不运行生产实现
/// 就自行复述公式。
abstract final class AvatarCropConstraints {
  static double minimumScale(double rotationRadians) {
    final double cos = math.cos(rotationRadians).abs();
    final double sin = math.sin(rotationRadians).abs();
    return math.max(1, cos + sin);
  }

  static AvatarCropParams clamp({
    required AvatarCropParams params,
    required double imageWidth,
    required double imageHeight,
    required double cropSide,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0 || cropSide <= 0) {
      return const AvatarCropParams(
        scale: 1,
        rotationRadians: 0,
        offsetX: 0,
        offsetY: 0,
      );
    }
    final double minimum = minimumScale(params.rotationRadians);
    final double scale = params.scale.clamp(minimum, minimum * 4);
    final double half = cropSide / 2;
    final double cos = math.cos(params.rotationRadians);
    final double sin = math.sin(params.rotationRadians);
    final double cover = math.max(
      cropSide / imageWidth,
      cropSide / imageHeight,
    );
    final double halfWidth = imageWidth * cover * scale / 2;
    final double halfHeight = imageHeight * cover * scale / 2;
    final double support = (cos.abs() + sin.abs()) * half;
    final double limitX = math.max(halfWidth - support, 0);
    final double limitY = math.max(halfHeight - support, 0);
    final double tx = params.offsetX * cropSide;
    final double ty = params.offsetY * cropSide;
    final double rotatedX = cos * tx + sin * ty;
    final double rotatedY = -sin * tx + cos * ty;
    final double clampedX = rotatedX.clamp(-limitX, limitX);
    final double clampedY = rotatedY.clamp(-limitY, limitY);
    return AvatarCropParams(
      scale: scale,
      rotationRadians: params.rotationRadians,
      offsetX: (cos * clampedX - sin * clampedY) / cropSide,
      offsetY: (sin * clampedX + cos * clampedY) / cropSide,
    );
  }
}
