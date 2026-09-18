# 阶段 0 最小原型

此目录用于隔离的关键能力验证，不是正式业务工程。阶段与冻结状态只看[阶段状态与决策记录](../../docs/阶段状态与决策记录.md)。

- [行为对照矩阵](../../docs/阶段0行为对照矩阵.md)：页面、业务契约、UI与阶段0必验项。
- [关键原型报告](../../docs/阶段0关键原型报告.md)：已有会话Fake、Reader guard和真实WebView入口的断言边界，以及待补入口/设备证据。
- [依赖清单](../../docs/阶段0依赖锁定清单.md)：完整候选依赖与本目录最小原型lock的区别。

现有入口包括会话、API Cookie隔离、Reader guard/错误分类/共享回调及导航守卫单测，以及导航恢复、Cookie隔离、WebView生命周期、返回、错误分类和外部系统输入集成入口。`lib/reader_back_main.dart`用于正常安装包的双端系统手势专项。两个本地HTML asset只用于A→B历史、非零滚动和返回/刷新差异；网络专项仅访问运行时建立的localhost服务器。Android的localhost明文许可只存在于debug源集，主Manifest没有放宽。当前原型仍不能证明生产Dio/安全存储集成、渲染进程真实崩溃分类、普通站内导航收藏目标或原生WebView资源已释放；Router重建后非活动分支的命令式导航栈会丢失。

在本目录执行阶段0既有检查；设备ID按实际设备选择：

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter test integration_test -d <android-device-id>
flutter test integration_test -d <ios-simulator-id>
```

实际复验结果见原型报告第8～13节；命令清单本身不代表通过。当前最终版受控39/39、Analyze/21个Dart文件format及双端全目录integration均为7通过/1有意skip；Android外部系统输入入口必须显式传入`--dart-define=STAGE0_EXTERNAL_SYSTEM_INPUT=true`并由ADB配合。导航恢复使用Flutter测试框架的`restartAndRestore`并重建Router，不等于真实OS进程终止。完整候选依赖只为G09临时接入并完成双端debug构建，最终本目录已恢复WebView与导航最小依赖。尚未建立或失败的其他门禁仍为待验证。只使用Fake、固定虚构响应或受控页面，不访问真实账号/收藏写接口。受控逻辑、Android和iOS结果分别记录。

`ReaderProbeCallbacks` 同时用于真实Delegate与受控测试；日志区分platform/injected/timer。history/collection字段只是副作用探针。`restore`限启动恢复；清理返回false时不能宣称退出已持久化，重建仍可能读取旧身份为unverified。
