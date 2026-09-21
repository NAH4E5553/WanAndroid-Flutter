import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:wanandroid_flutter/src/data/repository/implementation/default_collection_repository.dart';
import 'package:wanandroid_flutter/src/data/storage/secure_session_storage.dart';
import 'package:wanandroid_flutter/src/data/storage/session_storage.dart';
import 'package:wanandroid_flutter/src/data/storage/theme_preferences.dart';

/// In-memory fallbacks keep lightweight tests (which render the app without
/// overriding every provider) working; the production bootstrap always
/// overrides these with the real wired stack.
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SessionStore(storage: MemorySessionStorage()),
);

class MemorySessionStorage implements SessionStorage {
  String? _payload;

  @override
  Future<String?> read() async => _payload;

  @override
  Future<void> write(String? payload) async => _payload = payload;
}

/// Composition used by the production bootstrap and mirrored in tests.
AppDependencies buildAppDependencies({ThemeStorage? themePreferences}) {
  final SessionStore sessionStore = SessionStore(
    storage: SecureSessionStorage(),
  );
  final Dio dio = createWanApiDio()
    ..interceptors.add(SessionInterceptor(sessionStore));
  final DioWanApiService service = DioWanApiService(dio: dio);
  final ArticleNetworkDataSource network = DefaultArticleNetworkDataSource(
    service,
  );
  final DefaultCollectionRepository collectionRepository =
      DefaultCollectionRepository(
        source: DefaultCollectionNetworkDataSource(service),
        sessions: sessionStore,
      );
  return AppDependencies(
    sessionStore: sessionStore,
    authRepository: DefaultAuthRepository(
      sessionStore: sessionStore,
      source: DefaultAuthNetworkDataSource(service),
      coordinator: SessionCommitCoordinator(),
    ),
    collectionRepository: collectionRepository,
    network: network,
    themeController: ThemeController(
      preferences: themePreferences ?? SharedPreferencesThemePreferences(),
    ),
  );
}

class AppDependencies {
  const AppDependencies({
    required this.sessionStore,
    required this.authRepository,
    required this.collectionRepository,
    required this.network,
    required this.themeController,
  });

  final SessionStore sessionStore;
  final AuthRepository authRepository;
  final CollectionRepository collectionRepository;
  final ArticleNetworkDataSource network;
  final ThemeController themeController;
}
