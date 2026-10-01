import 'dart:typed_data';

import '../../../model/album_models.dart';

abstract interface class AlbumRepository {
  Stream<void> get changes;
  Future<AlbumPermission> permission({bool request = false});
  Future<void> manageAccess();
  Future<void> openSettings();
  Future<AlbumSnapshot> snapshot();
  Future<Uint8List?> thumbnail(AlbumAsset asset, int size);
  Future<AlbumFileLease> prepare(
    AlbumAsset asset,
    AlbumBudget budget,
    AlbumCancellation cancellation, {
    required bool allowNetwork,
  });
  void clearImages();
  Future<void> close();
}
