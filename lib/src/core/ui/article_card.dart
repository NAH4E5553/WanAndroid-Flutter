import 'package:flutter/material.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

class ArticleCard extends StatelessWidget {
  const ArticleCard({
    required this.article,
    required this.onTap,
    this.showCategory = true,
    super.key,
  });

  final Article article;
  final VoidCallback onTap;
  final bool showCategory;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final WanSpacing spacing = context.spacing;
    final String byline = article.author.isNotEmpty
        ? '作者：${article.author}'
        : '分享者：${article.shareUser.isEmpty ? '未知' : article.shareUser}';
    final String category = <String>[
      article.superChapterName,
      article.chapter,
    ].where((String value) => value.isNotEmpty).join('/');
    return Semantics(
      button: true,
      label: '${article.title}，$byline，${article.publishedAt}',
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.page,
          vertical: spacing.small,
        ),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(spacing.page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: spacing.small,
                children: <Widget>[
                  Text(
                    article.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    byline,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  if (showCategory)
                    Text(
                      '分类：${category.isEmpty ? '未知' : category}',
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: colors.primary),
                    ),
                  Text(
                    '时间：${article.publishedAt}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
