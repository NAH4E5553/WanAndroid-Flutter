import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/app/app.dart';
import 'package:wanandroid_flutter/src/data/repository/implementation/fake_home_repository.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_view_model.dart';

void bootstrap() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      retry: (int retryCount, Object error) => null,
      overrides: [
        homeRepositoryProvider.overrideWithValue(const FakeHomeRepository()),
      ],
      child: const WanAndroidApp(),
    ),
  );
}
