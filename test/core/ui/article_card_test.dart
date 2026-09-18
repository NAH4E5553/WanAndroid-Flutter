import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/core/ui/article_card.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

void main() {
  testWidgets('renders title and metadata without an image placeholder', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: wanTheme(brightness: Brightness.light),
        home: Scaffold(
          body: ArticleCard(article: _article, onTap: () {}),
        ),
      ),
    );

    expect(find.text(_article.title), findsOneWidget);
    expect(find.text('分享者：示例分享者'), findsOneWidget);
    expect(find.text('分类：移动开发/Flutter'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('remains readable with 200 percent text scaling', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          theme: wanTheme(brightness: Brightness.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ArticleCard(article: _article, onTap: () {}),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(_article.title), findsOneWidget);
  });
}

const Article _article = Article(
  id: 102,
  title: '用于验证长标题换行与元信息层级的固定示例文章',
  url: 'https://fixture.invalid/articles/102',
  author: '',
  shareUser: '示例分享者',
  superChapterName: '移动开发',
  chapter: 'Flutter',
  publishedAt: '2026-09-18',
  collected: false,
);
