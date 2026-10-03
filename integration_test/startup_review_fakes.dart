import 'package:flutter/material.dart' show ThemeMode;
import 'package:wanandroid_flutter/src/core/cancellation/request_cancellation.dart';
import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/core/theme/theme_storage.dart';
import 'package:wanandroid_flutter/src/core/theme/wan_theme.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/article_repository.dart';
import 'package:wanandroid_flutter/src/data/repository/contract/search_suggestions_repository.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';
import 'package:wanandroid_flutter/src/model/search_history.dart';

/// STARTUP-02 连续录屏与性能对照专用固定 Fake。
///
/// 只为 `startup_review_entry.dart` 服务:数据内容固定虚构,
/// 文章与问答共用同一 [delay],使"快速就绪"与"延迟就绪"两种
/// 场景下两个数据块的条件保持一致。不触碰网络、持久化与真实账号。
class StartupReviewArticleRepository implements ArticleRepository {
  StartupReviewArticleRepository({required this.delay});

  /// 首页文章与问答共同的就绪延迟;快速场景为 Duration.zero。
  final Duration delay;

  @override
  Future<DataResult<PageResult<Article>>> articles(
    int page,
    RequestCancellation cancellation,
  ) async {
    await Future<void>.delayed(delay);
    return DataSuccess<PageResult<Article>>(
      PageResult<Article>(items: _articles, nextPage: null),
    );
  }

  @override
  Future<DataResult<List<Article>>> questions(
    RequestCancellation cancellation,
  ) async {
    await Future<void>.delayed(delay);
    return DataSuccess<List<Article>>(_questions);
  }

  @override
  Future<DataResult<PageResult<Article>>> questionPage(
    int page,
    RequestCancellation cancellation,
  ) => throw UnimplementedError();

  @override
  Future<DataResult<PageResult<Article>>> search(
    int page,
    String keyword,
    RequestCancellation cancellation,
  ) => throw UnimplementedError();
}

/// 固定浅色主题存储:无持久化 I/O,读取恒定成功。
/// 调色板与模式取生产默认值(slateBlue),仅把 system 固定为 light,
/// 保证录屏与性能样本的最终页面亮度可预期。
class StartupReviewThemeStorage implements ThemeStorage {
  const StartupReviewThemeStorage();

  @override
  Future<ThemeSelection?> read() async =>
      (palette: WanPalette.slateBlue, mode: ThemeMode.light);

  @override
  Future<void> write(WanPalette palette, ThemeMode mode) async {}
}

/// 冷启动链路不可达的搜索建议仓储:被意外调用时显式失败,
/// 绝不返回伪造的成功数据。
class StartupReviewSearchSuggestions implements SearchSuggestionsRepository {
  const StartupReviewSearchSuggestions();

  @override
  Future<SearchHistory> loadHistory() => throw UnimplementedError();

  @override
  Future<DataResult<List<String>>> hotKeys(RequestCancellation cancellation) =>
      throw UnimplementedError();

  @override
  Future<bool> record(String keyword) => throw UnimplementedError();

  @override
  Future<bool> clearHistory() => throw UnimplementedError();
}

const List<Article> _articles = <Article>[
  Article(
    id: 101,
    title: '启动测量文章一:固定数据标题',
    url: 'https://fixture.invalid/1',
    author: '测量作者',
    shareUser: '',
    superChapterName: '启动测量',
    chapter: '固定分类',
    publishedAt: '2026-10-02',
    collected: false,
  ),
  Article(
    id: 102,
    title: '启动测量文章二:固定数据标题',
    url: 'https://fixture.invalid/2',
    author: '测量作者',
    shareUser: '',
    superChapterName: '启动测量',
    chapter: '固定分类',
    publishedAt: '2026-10-02',
    collected: false,
  ),
  Article(
    id: 103,
    title: '启动测量文章三:固定数据标题',
    url: 'https://fixture.invalid/3',
    author: '测量作者',
    shareUser: '',
    superChapterName: '启动测量',
    chapter: '固定分类',
    publishedAt: '2026-10-02',
    collected: false,
  ),
  Article(
    id: 104,
    title: '启动测量文章四:固定数据标题',
    url: 'https://fixture.invalid/4',
    author: '测量作者',
    shareUser: '',
    superChapterName: '启动测量',
    chapter: '固定分类',
    publishedAt: '2026-10-02',
    collected: false,
  ),
];

const List<Article> _questions = <Article>[
  Article(
    id: 201,
    title: '启动测量问答一:固定数据标题',
    url: 'https://fixture.invalid/q1',
    author: '测量作者',
    shareUser: '',
    superChapterName: '启动测量',
    chapter: '问答',
    publishedAt: '2026-10-02',
    collected: false,
  ),
  Article(
    id: 202,
    title: '启动测量问答二:固定数据标题',
    url: 'https://fixture.invalid/q2',
    author: '测量作者',
    shareUser: '',
    superChapterName: '启动测量',
    chapter: '问答',
    publishedAt: '2026-10-02',
    collected: false,
  ),
];
