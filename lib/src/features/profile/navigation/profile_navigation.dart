import 'package:flutter/widgets.dart';
import 'package:wanandroid_flutter/src/features/profile/view/collections_screen.dart';
import 'package:wanandroid_flutter/src/features/profile/view/profile_screen.dart';
import 'package:wanandroid_flutter/src/features/profile/view/reading_history_screen.dart';
import 'package:wanandroid_flutter/src/features/profile/view/theme_settings_screen.dart';

Widget buildProfileScreen({
  required VoidCallback onHistoryTap,
  required VoidCallback onCollectionsTap,
  required VoidCallback onThemeTap,
  required VoidCallback onLoginTap,
}) => ProfileScreen(
  onHistoryTap: onHistoryTap,
  onCollectionsTap: onCollectionsTap,
  onThemeTap: onThemeTap,
  onLoginTap: onLoginTap,
);

Widget buildReadingHistoryScreen({
  required VoidCallback onBack,
  required VoidCallback onPopped,
  required void Function(String url, String title, int? articleId) onRead,
}) => ReadingHistoryScreen(onBack: onBack, onPopped: onPopped, onRead: onRead);

Widget buildCollectionsScreen({
  required VoidCallback onBack,
  required VoidCallback onLoginTap,
  required void Function(String url, String title, int? articleId) onArticleTap,
}) => CollectionsScreen(
  onBack: onBack,
  onLoginTap: onLoginTap,
  onArticleTap: onArticleTap,
);

Widget buildThemeSettingsScreen({required VoidCallback onBack}) =>
    ThemeSettingsScreen(onBack: onBack);
