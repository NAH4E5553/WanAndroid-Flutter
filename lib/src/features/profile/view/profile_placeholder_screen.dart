import 'package:flutter/material.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';

class ProfilePlaceholderScreen extends StatelessWidget {
  const ProfilePlaceholderScreen({required this.onHistoryTap, super.key});

  final VoidCallback onHistoryTap;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(context.spacing.section),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: context.spacing.medium,
        children: <Widget>[
          Icon(
            Icons.person_outline,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          Text('我的', style: Theme.of(context).textTheme.headlineSmall),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('阅读历史'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onHistoryTap,
          ),
          const Text('登录、收藏与主题持久化将在阶段 5 实现。'),
        ],
      ),
    ),
  );
}
