import 'package:flutter/material.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/core/ui/app_scaffold.dart';
import 'package:wanandroid_flutter/src/core/ui/app_top_bar.dart';

class HomePreviewScreen extends StatelessWidget {
  const HomePreviewScreen({
    required this.articleId,
    required this.title,
    required this.onBack,
    required this.onPopped,
    super.key,
  });

  final int articleId;
  final String title;
  final VoidCallback onBack;
  final VoidCallback onPopped;

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    onPopInvokedWithResult: (bool didPop, Object? result) {
      if (didPop) {
        onPopped();
      }
    },
    child: AppScaffold(
      topBar: AppTopBar(title: title, onBack: onBack),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(context.spacing.section),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: context.spacing.medium,
            children: <Widget>[
              Icon(
                Icons.description_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              Text(
                '文章预览 #$articleId',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Text('阶段 1 只验证导航、主题和组件调用链；生产阅读器将在阶段 4 实现。'),
            ],
          ),
        ),
      ),
    ),
  );
}
