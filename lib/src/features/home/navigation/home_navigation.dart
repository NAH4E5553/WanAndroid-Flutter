import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanandroid_flutter/src/features/home/view/daily_questions_screen.dart';
import 'package:wanandroid_flutter/src/features/home/view/home_screen.dart';
import 'package:wanandroid_flutter/src/features/home/view/search_screen.dart';
import 'package:wanandroid_flutter/src/features/home/view_model/home_dependencies.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

Widget buildHomeScreen({
  required ValueChanged<Article> onArticleTap,
  required VoidCallback onSearchTap,
  required VoidCallback onViewAllQuestions,
}) => HomeScreen(
  onArticleTap: onArticleTap,
  onSearchTap: onSearchTap,
  onViewAllQuestions: onViewAllQuestions,
);

Widget buildSearchScreen({
  required String routeInstanceId,
  required VoidCallback onBack,
  required ValueChanged<Article> onArticleTap,
}) => ProviderScope(
  overrides: [
    homeChildRouteInstanceProvider.overrideWithValue(routeInstanceId),
  ],
  child: SearchScreen(onBack: onBack, onArticleTap: onArticleTap),
);

Widget buildDailyQuestionsScreen({
  required String routeInstanceId,
  required VoidCallback onBack,
  required ValueChanged<Article> onArticleTap,
}) => ProviderScope(
  overrides: [
    homeChildRouteInstanceProvider.overrideWithValue(routeInstanceId),
  ],
  child: DailyQuestionsScreen(onBack: onBack, onArticleTap: onArticleTap),
);
