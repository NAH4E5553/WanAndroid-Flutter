import 'package:image_picker/image_picker.dart';
import 'package:wanandroid_flutter/src/model/avatar.dart';

/// Gateway to the system camera and system photo picker. The app never reads
/// the gallery directly: it only receives the single user-picked file.
abstract interface class AvatarImageSourceGateway {
  /// Opens the external system page. Must be treated as a process-lifetime
  /// boundary on Android: the app may be killed while it is open.
  Future<AvatarPickOutcome> pick({required AvatarSource source});

  /// One-shot recovery of the result lost to an Android process kill. Must
  /// be called once per process, after the session restore finished.
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
        // The full-resolution image is required: the user may zoom into any
        // region before the 1:1 crop, and orientation normalization runs on
        // the decoded pixels.
        requestFullMetadata: false,
      );
      if (file == null) {
        return AvatarPickOutcome.cancelled;
      }
      return AvatarPickOutcome.ready(file.path);
    } on Object {
      // System page unavailable (no camera app, picker crashed, plugin
      // error). The caller shows failure feedback and keeps the avatar.
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
