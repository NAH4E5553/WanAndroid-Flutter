# WanAndroid Flutter

当前处于“阶段 1：工程骨架与设计系统”。正式工程使用固定 Fake 数据验证主题、基础组件、首页垂直切片和三分支导航恢复；生产网络、WebView、登录、收藏、视觉验收、真实进程恢复与发布检查不属于本阶段实现。

## 阶段 1 检查

```bash
dart run build_runner build
dart --packages=tool/standalone_package_config.json tool/generate_launcher_icons.dart
dart format --output=none --set-exit-if-changed .
dart --packages=tool/standalone_package_config.json tool/analyze_project.dart
dart --packages=tool/standalone_package_config.json tool/verify_architecture.dart
dart --packages=tool/standalone_package_config.json tool/verify_architecture_fixtures.dart
dart --packages=tool/standalone_package_config.json tool/verify_stage1.dart
flutter analyze
flutter test
flutter test integration_test -d <device-id>
flutter build apk --debug
flutter build ios --simulator --debug
```

依赖解析必须保持根目录 `pubspec.lock` 与 `stage0/dependency_lock/pubspec.lock` 字节一致。
