import 'package:flutter/widgets.dart';
import 'package:wanandroid_flutter/src/features/profile/view/profile_placeholder_screen.dart';
import 'package:wanandroid_flutter/src/features/profile/view/reading_history_screen.dart';

Widget buildProfileScreen({required VoidCallback onHistoryTap}) =>
    ProfilePlaceholderScreen(onHistoryTap: onHistoryTap);

Widget buildReadingHistoryScreen({
  required VoidCallback onBack,
  required VoidCallback onPopped,
  required void Function(String url, String title, int? articleId) onRead,
}) => ReadingHistoryScreen(onBack: onBack, onPopped: onPopped, onRead: onRead);
