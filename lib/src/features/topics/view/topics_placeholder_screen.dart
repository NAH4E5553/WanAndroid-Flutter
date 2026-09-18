import 'package:flutter/material.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';

class TopicsPlaceholderScreen extends StatelessWidget {
  const TopicsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(context.spacing.section),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: context.spacing.medium,
        children: <Widget>[
          Icon(
            Icons.grid_view_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          Text('专题', style: Theme.of(context).textTheme.headlineSmall),
          const Text('专题完整交互将在阶段 3 实现。'),
        ],
      ),
    ),
  );
}
