import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/features/home/component/daily_question_card.dart';
import 'package:wanandroid_flutter/src/model/article.dart';

void main() {
  testWidgets('clips the accent line to the rounded card boundary', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: wanTheme(brightness: Brightness.light),
        home: Scaffold(
          body: DailyQuestionCard(
            question: _question,
            position: 0,
            count: 2,
            onTap: () {},
          ),
        ),
      ),
    );

    final Finder cardFinder = find.descendant(
      of: find.byType(DailyQuestionCard),
      matching: find.byType(Card),
    );
    final Card card = tester.widget<Card>(cardFinder);

    expect(card.clipBehavior, Clip.antiAlias);
    expect(tester.takeException(), isNull);
  });

  for (final (double scale, double height) in <(double, double)>[
    (1, 156),
    (2, 228),
  ]) {
    testWidgets('limits a long title to three lines at ${scale}x text scale', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: wanTheme(brightness: Brightness.light),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Center(
                child: SizedBox(
                  width: 390,
                  height: height,
                  child: DailyQuestionCard(
                    question: _longQuestion,
                    position: 0,
                    count: 2,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final Finder titleFinder = find.text(_longQuestion.title);
      final Text title = tester.widget<Text>(titleFinder);
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        titleFinder,
      );
      expect(title.maxLines, 3);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(paragraph.didExceedMaxLines, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}

const Article _question = Article(
  id: 201,
  title: 'Flutter 中如何保持页面状态与导航状态一致？',
  url: 'https://fixture.invalid/questions/201',
  author: '示例作者',
  shareUser: '',
  superChapterName: '每日一问',
  chapter: 'Flutter',
  publishedAt: '2026-09-18 09:30',
  collected: false,
);

const Article _longQuestion = Article(
  id: 202,
  title: 'Flutter 中如何保持页面状态与导航状态一致？当多个页面同时加载文章、切换底部导航并恢复先前的页面栈时，怎样避免旧请求覆盖新状态？',
  url: 'https://fixture.invalid/questions/202',
  author: '示例作者',
  shareUser: '',
  superChapterName: '每日一问',
  chapter: 'Flutter',
  publishedAt: '2026-09-18 09:30',
  collected: false,
);
