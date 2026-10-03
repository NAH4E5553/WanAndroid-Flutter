import 'package:dio/dio.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_controller.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_storage.dart';
import 'package:wanandroid_flutter/src/data/network/article_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/network/auth_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/network/collection_network_data_source.dart';
import 'package:wanandroid_flutter/src/data/network/service/wan_api_service.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_commit_coordinator.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_interceptor.dart';
import 'package:wanandroid_flutter/src/data/network/session/session_store.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/collection_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_auth_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_avatar_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/default_collection_repository.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_file_storage.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_gallery_gateway.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_image_normalization_gateway.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_image_processor.dart';
import 'package:wanandroid_flutter/src/data/storage/avatar_image_source_gateway.dart';
import 'package:wanandroid_flutter/src/data/storage/secure_session_storage.dart';
import 'package:wanandroid_flutter/src/data/storage/theme_preferences.dart';

/// 生产 bootstrap 使用的组装,并在测试中保持一致的镜像。
AppDependencies buildAppDependencies({ThemeStorage? themePreferences}) {
  final SessionStore sessionStore = SessionStore(
    storage: SecureSessionStorage(),
  );
  final SessionCommitCoordinator sessionCoordinator =
      SessionCommitCoordinator();
  final Dio dio = createWanApiDio()
    ..interceptors.add(SessionInterceptor(sessionStore, sessionCoordinator));
  final DioWanApiService service = DioWanApiService(dio: dio);
  final ArticleNetworkDataSource network = DefaultArticleNetworkDataSource(
    service,
    sessionStore,
  );
  final DefaultCollectionRepository collectionRepository =
      DefaultCollectionRepository(
        source: DefaultCollectionNetworkDataSource(service),
        sessions: sessionStore,
      );
  final DefaultAuthRepository authRepository = DefaultAuthRepository(
    sessionStore: sessionStore,
    source: DefaultAuthNetworkDataSource(service),
    coordinator: sessionCoordinator,
  );
  final ChannelAvatarGalleryGateway avatarGalleryGateway =
      ChannelAvatarGalleryGateway();
  final DefaultAvatarRepository avatarRepository = DefaultAvatarRepository(
    authRepository: authRepository,
    sourceGateway: ImagePickerAvatarImageSourceGateway(),
    galleryGateway: avatarGalleryGateway,
    normalizationGateway: const ChannelAvatarImageNormalizationGateway(),
    processor: const UiAvatarImageProcessor(),
    storage: AvatarFileStorage(
      directories: const PathProviderAvatarDirectories(),
      excludeFromBackup: avatarGalleryGateway.excludeFromBackup,
    ),
  );
  return AppDependencies(
    avatarRepository: avatarRepository,
    authRepository: authRepository,
    collectionRepository: collectionRepository,
    network: network,
    themeController: ThemeController(
      preferences: themePreferences ?? SharedPreferencesThemePreferences(),
    ),
  );
}

class AppDependencies {
  const AppDependencies({
    required this.avatarRepository,
    required this.authRepository,
    required this.collectionRepository,
    required this.network,
    required this.themeController,
  });

  final DefaultAvatarRepository avatarRepository;
  final AuthRepository authRepository;
  final CollectionRepository collectionRepository;
  final ArticleNetworkDataSource network;
  final ThemeController themeController;
}
