import 'package:image_picker/image_picker.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';

/// 系统相机和系统照片选择器的网关。应用从不直接读取相册:
/// 只接收用户挑选的那一个文件。
abstract interface class AvatarImageSourceGateway {
  /// 打开外部系统页面。在 Android 上必须视为进程生命周期边界:
  /// 页面打开期间应用可能被杀。
  Future<AvatarPickOutcome> pick({required AvatarSource source});

  /// 对因 Android 进程被杀而丢失结果的一次性恢复。每个进程
  /// 只能调用一次,且必须在会话恢复完成之后。
  Future<AvatarPickOutcome> retrieveLostData();
}

final class ImagePickerAvatarImageSourceGateway
    implements AvatarImageSourceGateway {
  ImagePickerAvatarImageSourceGateway({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<AvatarPickOutcome> pick({required AvatarSource source}) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source == AvatarSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        // 必须使用全分辨率图像:用户在 1:1 裁剪前
        // 可能放大到任意区域,且方向归一化
        // 在解码后的像素上执行。
        requestFullMetadata: false,
      );
      if (file == null) {
        return AvatarPickOutcome.cancelled;
      }
      return AvatarPickOutcome.ready(file.path);
    } on Object {
      // 系统页面不可用(无相机应用、选择器崩溃、插件错误)。
      // 调用方展示失败反馈并保留现有头像。
      return AvatarPickOutcome.unavailable;
    }
  }

  @override
  Future<AvatarPickOutcome> retrieveLostData() async {
    try {
      final LostDataResponse response = await _picker.retrieveLostData();
      if (response.isEmpty) {
        return AvatarPickOutcome.cancelled;
      }
      final XFile? file = response.file;
      if (file != null) {
        return AvatarPickOutcome.ready(file.path);
      }
      if (response.exception != null) {
        return AvatarPickOutcome.unavailable;
      }
      return AvatarPickOutcome.cancelled;
    } on Object {
      return AvatarPickOutcome.unavailable;
    }
  }
}
