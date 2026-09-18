import 'package:wanandroid_flutter/src/data/repository/contract/home_repository.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/home_feed.dart';

class FakeHomeRepository implements HomeRepository {
  const FakeHomeRepository();

  @override
  Future<HomeFeed> loadHome() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return const HomeFeed(
      questions: <Article>[
        Article(
          id: 201,
          title: 'Flutter 中如何保持页面状态与导航状态一致？',
          url: 'https://fixture.invalid/questions/201',
          author: '示例作者',
          shareUser: '',
          superChapterName: '每日一问',
          chapter: 'Flutter',
          publishedAt: '2026-09-18 09:30',
          collected: false,
        ),
        Article(
          id: 202,
          title: '复杂列表在刷新与追加并发时应如何隔离旧结果？',
          url: 'https://fixture.invalid/questions/202',
          author: '',
          shareUser: '示例分享者',
          superChapterName: '每日一问',
          chapter: '架构',
          publishedAt: '2026-09-17 18:20',
          collected: false,
        ),
      ],
      articles: <Article>[
        Article(
          id: 101,
          title: '用固定 Fake 数据建立第一个 Flutter 垂直切片',
          url: 'https://fixture.invalid/articles/101',
          author: '示例作者',
          shareUser: '',
          superChapterName: '开发实践',
          chapter: 'Flutter',
          publishedAt: '2026-09-18 08:00',
          collected: false,
        ),
        Article(
          id: 102,
          title: '一篇用于验证长标题换行、元信息层级与大字体布局的固定示例文章',
          url: 'https://fixture.invalid/articles/102',
          author: '',
          shareUser: '示例分享者',
          superChapterName: '移动开发',
          chapter: '设计系统',
          publishedAt: '2026-09-17 16:45',
          collected: true,
        ),
        Article(
          id: 103,
          title: '非活动分支栈恢复：从已知失败到可执行门禁',
          url: 'https://fixture.invalid/articles/103',
          author: '示例作者',
          shareUser: '',
          superChapterName: '架构',
          chapter: '导航',
          publishedAt: '2026-09-16 12:10',
          collected: false,
        ),
      ],
    );
  }
}
