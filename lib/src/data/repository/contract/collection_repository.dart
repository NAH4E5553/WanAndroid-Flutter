import 'package:wanandroid_flutter/src/core/result/data_result.dart';
import 'package:wanandroid_flutter/src/model/article.dart';
import 'package:wanandroid_flutter/src/model/collection.dart';
import 'package:wanandroid_flutter/src/model/page_result.dart';

/// 按账号划定作用域的收藏(collect)状态权威。
/// 没有后台作用域、没有排队写入,也没有乐观成功;
/// 以下每一条规则都与已冻结的收藏契约一一对应。
abstract interface class CollectionRepository {
  /// 可观察的快照;listener 仅在状态发生变迁时触发。
  CollectionSnapshot get current;

  void addListener(void Function() listener);

  void removeListener(void Function() listener);

  /// 包装一次公开文章列表的加载:加载前捕获会话与写版本,
  /// 之后只合并有资格采纳的服务端提示,
  /// 并在条目状态已知时为其标注会话键。
  Future<DataResult<PageResult<Article>>> articlePage(
    Future<DataResult<PageResult<Article>>> Function() load,
  );

  /// 加载已登录账号收藏列表中的一页。
  Future<DataResult<PageResult<CollectionItem>>> page(int generation, int page);

  /// 针对未知状态的只读核对:只有翻到列表末尾才能确认存在;
  /// 有界(未翻完)或失败的扫描保持未知。
  Future<DataResult<void>> reconcile(int generation, CollectionTarget target);

  /// 驱动的是用户明确表达的目标,
  /// 绝不是对最新已知布尔值的盲目切换。
  Future<DataResult<void>> setCollected(
    int generation,
    CollectionTarget target,
    bool collected,
  );
}
