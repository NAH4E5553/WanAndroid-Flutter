# WanAndroid Flutter 版本实施方案（契约补强稿）

> 文档状态：2026-09-18用户完整接受阶段0关键原型报告15.3推荐值；阶段1～3分别经PR #1、#2、#6及远端CI验证；阶段3交付已合并，仍停留阶段3，未经授权不进入阶段4。冻结不代表后续WebView、登录、收藏、视觉验收、真实进程恢复或发布检查已经实现。
> 当前阶段、验证结果与冻结决定以 `docs/阶段状态与决策记录.md` 为唯一权威入口；本行只描述方案定位。  
> Android 参考基线：`/Users/sn/Desktop/workplace/WanAndroid-AI`  
> 基线提交：`78cdaade84ef24ebbe825041b499cbe1cd7ee286`  
> 整理日期：2026-09-17

2026-09-18阶段0文档接入：[行为对照矩阵](docs/阶段0行为对照矩阵.md)、[关键原型报告](docs/阶段0关键原型报告.md)、[依赖清单](docs/阶段0依赖锁定清单.md)。UI还原细则见[UI基线与还原规范](/Users/sn/Desktop/workplace/WanAndroid-AI/docs/local/Flutter-UI基线与还原规范.md)，其编号已并入同一矩阵；素材审计、原型和依赖的最新证据及边界以阶段文档和状态入口为准。阶段0推荐值已冻结，但阶段文档中保留的历史“候选/待确认”措辞只描述当时状态，不能覆盖状态入口或扩大实现结论。

## 1. 目标与原则

以当前 WanAndroid Android 版本为功能、交互和安全行为基线，开发独立的 Android/iOS Flutter 应用。

迁移不是把 Kotlin 代码逐行翻译成 Dart，而是保持以下契约可追溯且行为一致：

- Screen → ViewModel → Repository → DataSource/Service 的调用方向。
- 不可变页面状态、单一数据源和单向数据流。
- 请求取消、请求代次、旧结果隔离和账号隔离。
- 文章从第 0 页、问答从第 1 页开始的接口语义。
- 刷新、追加、分阶段错误、去重和分页暂停机制。
- 登录回跳但不自动重放收藏写操作。
- WebView、Cookie、外部跳转和日志脱敏安全边界。
- 四套配色、深浅模式、专题切换及列表左滑操作等已确认 UI 行为。

第一阶段只对齐 Android 基线已经实现的能力，不提前实现正文离线缓存、注册、找回密码、资料编辑、推送、后台批量下载或云端历史同步。

## 2. Flutter 官方架构结论

Flutter 官方当前推荐以 MVVM 为核心，将应用分成 UI 层和数据层：

- UI 层由 View 和 ViewModel 组成。
- 数据层由 Repository 和 Service 组成。
- 使用单一数据源、不可变状态和单向数据流。
- 使用依赖注入，使 Repository、Service 和平台能力可以替换和测试。
- Domain/UseCase 层是可选层，只在复杂业务或重复逻辑确实出现时引入。
- 官方推荐大多数应用使用 `go_router`，而不是旧式命名路由。
- 状态管理库没有唯一强制答案；`ChangeNotifier` 是条件性建议，不是架构本身。

本项目采用官方分层原则，但状态管理选择 Riverpod，以便更自然地表达不可变状态、页面实例隔离、依赖覆盖和测试替身。

参考资料：

- [Flutter 官方架构指南](https://docs.flutter.dev/app-architecture/guide)
- [Flutter 官方架构建议](https://docs.flutter.dev/app-architecture/recommendations)
- [Flutter 状态管理概览](https://docs.flutter.dev/data-and-backend/state-mgmt)

## 3. 推荐技术栈

| 能力 | 推荐方案 | 决策理由 |
|---|---|---|
| 架构 | 官方 MVVM + Repository/Service | 与现有 Android 调用链接近 |
| 状态管理和依赖注入 | Riverpod | 不可变状态、实例隔离、Provider 覆盖和测试能力较适合本项目 |
| 网络 | Dio | 支持拦截器、取消、超时、自定义适配器 |
| JSON | `json_serializable` | 明确 DTO 解析规则并减少手写错误 |
| 不可变模型 | Dart sealed class + Freezed（按需） | Result 优先用 Dart 原生 sealed class；复杂 UiState/Model 使用 Freezed |
| 结果契约 | `DataResult<T>` | 只表达成功或业务错误，不承载 Loading、Toast 或日志 |
| 分页 | 迁移现有 PagingController 契约 | 保留项目特有的分页、取消、去重及暂停行为 |
| 导航 | `go_router` 类型安全路由 | Flutter 官方推荐，支持 Shell、深链、重定向和状态恢复 |
| 普通偏好 | `shared_preferences` 异步 API | 仅保存主题、显示模式、搜索历史等少量键值 |
| 敏感数据 | `flutter_secure_storage` | Android 加密存储、iOS Keychain |
| 结构化数据 | Drift/SQLite | 接近 Room，提供 DAO、事务、迁移和响应式查询 |
| 阅读器 | 官方 `webview_flutter` | Android WebView 与 iOS WKWebView |
| 外部链接 | 官方 `url_launcher` | 浏览器、电话、邮件及地图 Scheme |
| 权限 | 首版不引入通用权限库 | 当前已实现功能没有必须申请的运行时权限 |
| 测试 | unit + widget + integration | 分别覆盖逻辑、组件和真实设备流程 |

### 3.1 为什么网络选择 Dio

Flutter 官方网络教程使用轻量的 `package:http`，适合简单请求。但本项目包含：

- Cookie 域、路径、Secure 和有效期处理。
- 请求代次与账号切换隔离。
- 请求取消和超时。
- Release 日志脱敏。
- 禁止自动重定向。
- 写操作结果不确定时禁止盲目重试。

Dio 原生提供 Interceptor、CancelToken、Timeout 和 Adapter，更适合作为底层客户端。Dio 只允许在 Network Service/DataSource 内使用，Repository、ViewModel 和 Widget 不能直接依赖 Dio 类型。

取消信号使用项目自己的最小契约穿过分层，不向上暴露 `CancelToken`：

```dart
abstract interface class RequestCancellation {
  bool get isCancelled;
  Future<void> get whenCancelled;
  void throwIfCancelled();
}

abstract interface class RequestCancellationController {
  RequestCancellation get signal;
  void cancel();
}
```

- ViewModel 或 PagingController 为每个请求创建独立 Controller，只把只读 signal 传给下层，并在查询变化、刷新替换、页面销毁或 Provider dispose 时取消。
- Repository 只接收项目契约并继续向下传递，不导入 Dio。
- NetworkDataSource 将该信号桥接为当前请求专用的 `CancelToken`；不能多个无关请求共用一个 Token。
- 数据层在昂贵映射及提交结果前再次执行 `throwIfCancelled()`；请求代次仍是拒绝迟到结果的最终保障。
- 取消尚未完成的读取可以丢弃结果；收藏等写请求一旦已经发出，取消只表示调用方停止等待，不能推断服务器未执行，必须进入“状态不确定并核对”流程。

参考：

- [Flutter 官方网络文档](https://docs.flutter.dev/cookbook/networking)
- [Dio 文档](https://pub.dev/documentation/dio/latest/)
- [`json_serializable`](https://pub.dev/packages/json_serializable)

## 4. 工程与目录结构

第一版使用单 Flutter Package 和严格目录边界，不提前拆分大量本地 Package：

```text
lib/src/
├── app/
│   ├── bootstrap/
│   ├── router/
│   └── app.dart
├── core/
│   ├── result/
│   ├── paging/
│   ├── navigation/
│   ├── theme/
│   ├── ui/
│   └── platform/
├── data/
│   ├── network/
│   │   ├── dto/
│   │   ├── service/
│   │   ├── interceptor/
│   │   └── session/
│   ├── database/
│   ├── storage/
│   ├── mapper/
│   └── repository/
├── model/
└── features/
    ├── home/
    ├── topics/
    ├── article/
    ├── auth/
    └── profile/
```

Feature 内部按实际职责组织：

```text
home/
├── view/
├── view_model/
├── state/
└── component/
```

对应关系：

| Android | Flutter |
|---|---|
| Compose Screen | Flutter Screen/Widget |
| ViewModel + StateFlow | Riverpod Notifier + immutable UiState |
| Hilt | Riverpod Provider |
| Retrofit Service | Dio Service |
| Room | Drift |
| DataStore | PreferencesStorage |
| Navigation3 Graph | go_router typed route |
| core:ui | core/ui |
| core:designsystem | ThemeData + ThemeExtension |

初期保持单包可降低代码生成、依赖和构建维护成本，同时增加架构检查，禁止 Feature 互相依赖实现。只有出现独立发布、明显构建瓶颈或多人并行边界后，才把 Core 拆成本地 Dart Package。

### 4.1 允许的 import 方向

单包不代表没有模块边界。首个提交必须落地可执行的 import 检查，规则如下：

| 来源 | 允许依赖 | 明确禁止 |
|---|---|---|
| `app` | Feature 的公开路由声明、`core`、`model` | Feature 内部 ViewModel/Repository 实现 |
| `features/<name>/view` | 同 Feature 的 state/view_model/component/policy、`core/ui`、`core/navigation`、`model` | Dio、网络 DTO、Drift 表/DAO、其他 Feature 实现 |
| `features/<name>/view_model` | 同 Feature state/policy、Repository 接口、`core/result`、`core/paging`、`model` | Widget、Dio、网络 DTO、数据库实现、其他 Feature 实现 |
| `data/repository` | Repository 接口、DataSource、Mapper、DTO/Entity、`core/result`、`model` | Feature、Widget、路由实现 |
| `data/network` | Dio、网络 DTO、会话传输类型、`core/result` | Feature、Widget、数据库实现 |
| `data/database`、`data/storage` | Drift/平台存储插件及本层类型 | Feature、路由、网络实现 |
| `core/ui`、`core/theme` | Flutter UI、通用展示参数、设计 Token | Repository、Dio、DTO、数据库、业务 Feature |
| `core/paging` | `core/result`、纯 Dart 模型和取消契约 | Flutter Widget、Dio、具体 Repository |
| `core/navigation` | 可序列化路由/导航契约 | 数据层、具体 Feature 实现 |

- Feature 在自己的 `navigation/` 声明类型化路由及页面工厂，`app/router` 只聚合，不反向访问 Feature 私有实现。
- `navigation/`、`policy/`、`component/` 仅在有真实代码时建立，不创建空分组。
- 架构检查采用仓库内脚本扫描 `package:` 和相对 import；例外必须是精确文件/规则并写明理由，不能整目录放行。
- CI 在 `flutter analyze` 前执行该检查；违反规则时输出来源文件、目标 import 和规则编号并失败。

## 5. 状态管理与分页

### 5.1 页面状态

简单单资源页面可以使用 `AsyncNotifier<T>`。首页、专题、搜索、收藏等页面使用专门的不可变 UiState，不强行压缩成一个 `AsyncValue<List<T>>`，因为它们需要同时表达：

- 初次加载。
- 保留旧列表的刷新。
- 追加加载。
- 初次、刷新、追加三类失败和重试。
- 首页文章与问答两个独立请求。
- 专题分类状态、分页和滚动位置隔离。

示意：

```dart
class HomeUiState {
  const HomeUiState({
    required this.articles,
    required this.questions,
  });

  final PagingState<Article> articles;
  final QuestionState questions;
}
```

Widget 只渲染 UiState 并调用 ViewModel 公开方法，不取得 Repository、Dio、数据库或平台插件。

Provider 生命周期不能统一使用 `autoDispose` 或 `keepAlive`，按职责冻结如下：

| 对象 | 生命周期与释放规则 |
|---|---|
| 会话仓储、收藏仓储、主题仓储、数据库 | 应用级唯一实例；由根 `ProviderScope` 持有，测试时可覆盖 |
| 搜索 ViewModel、阅读 ViewModel | 按路由实例 ID 隔离并自动释放；即使文章参数相同，两个路由实例也不能共享页面状态 |
| 首页状态 | Shell 首页分支存活期间保留；退出登录只失效账号相关数据，不销毁公开列表 |
| 专题分类分页 | 以真实分类 ID 为参数；分类不可见时暂停网络和滚动监听，返回时续接；设定容量或空闲回收策略，不能无限保留所有参数组合 |
| 收藏列表 | 当前账号会话 + 路由实例隔离；换号立即失效，离开路由后释放页面分页状态，仓储事实仍保留 |
| 首页问答轮播/计时器 | Tab 不可见、路由被覆盖或 App 进入后台时停止，恢复可见后续接，不因计时器发网络请求 |

使用 Riverpod 代码生成时，参数化 Provider 默认自动释放。确需保留成功结果时使用显式、可撤销的 `keepAlive` 或有限缓存策略，并在 `onDispose` 释放请求、订阅与计时器。Riverpod 3 对 Provider 计算期间抛出的部分异常会自动重试，因此根 `ProviderScope` 默认关闭隐式重试；读取重试由页面/分页契约显式驱动，收藏、登录、退出等写操作绝不放在可能重复计算的 Provider 初始化中，也不接受隐式重放。

参考：

- [Riverpod 自动释放](https://riverpod.dev/docs/concepts2/auto_dispose)
- [Riverpod 自动重试](https://riverpod.dev/docs/concepts2/retry)

### 5.2 PagingController 迁移契约

Flutter 版保留现有 PagingController 的行为：

- 文章初始页为 0，问答初始页为 1。
- 页码只在成功后推进。
- PagingController 只持有项目的 `RequestCancellation`；网络层转换为 `CancelToken` 以尽快取消，请求代次仍是防止旧结果提交的最终保障。
- 查询、账号或分类变化后，旧结果不得提交。
- 追加时按稳定业务 ID 去重，同 ID 新内容覆盖旧内容。
- 连续两页没有新增 ID 时暂停自动加载。
- 用户点击“继续加载”后只请求一页；仍无新增则继续暂停。
- 初次、刷新和追加失败有各自重试入口。
- 专题每个真实二级分类 ID 独立持有分页状态和滚动状态。
- 首页组合文章分页和问答状态，不为继承基类而塞进单列表模型。
- 页面/Provider 释放时取消当前请求并停止滚动触发；取消收尾不得覆盖新代次的状态。

不直接使用普通无限列表插件替换该状态机；第三方插件通常无法完整表达这些业务规则。

## 6. 网络、结果和会话

调用链：

```text
Screen
  → ViewModel
    → Repository
      → NetworkDataSource
        → WanApiService
          → Dio
```

### 6.1 统一结果契约

使用 Dart sealed class：

```dart
sealed class DataResult<T> {
  const DataResult();
}

final class DataSuccess<T> extends DataResult<T> {
  const DataSuccess(this.value);
  final T value;
}

final class DataFailure<T> extends DataResult<T> {
  const DataFailure(this.error);
  final DataError error;
}
```

`DataResult` 不表示 Loading，不保存 Throwable，不负责 Toast 或日志。

### 6.2 WanAndroid 响应映射

- `errorCode` 缺失或类型错误时返回 `INVALID_RESPONSE`，不能默认成功。
- `errorCode == -1001` 映射为 `SESSION_EXPIRED`。
- 其他非零值映射为服务端业务失败。
- 读取接口成功但 `data == null` 是错误。
- 收藏、取消收藏、退出等无正文接口映射为 `DataResult<void>`。
- DTO 转业务模型只在 Repository/Mapper 完成。
- 取消继续传播，不伪装成网络错误。

### 6.3 网络安全

- Base URL 固定为 `https://wanandroid.com/`。
- 禁止自动重定向。
- API Cookie 不注入第三方阅读站点或 WebView。
- Release 禁止请求/响应正文日志。
- Debug 日志也必须移除密码、Cookie、Set-Cookie 和完整登录请求体。
- 写操作超时或断线时，不自动重试；先通过只读查询校准状态。

### 6.4 登录会话

会话状态包含账号身份、Cookie 快照、会话 ID 和请求代次。每个请求在发出前捕获不可变 `SessionRequest`；Cookie 注入、响应 Cookie 更新、401/`-1001` 过期处理和业务结果提交都必须校验该捕获值仍属于当前有效会话。登录流程先隔离响应 Cookie，只有业务响应、身份解析和加密持久化全部成功后，才发布已登录状态。

由于安全存储读写是异步操作，会话不能只靠写入前的一次代次判断。登录提交、普通响应 Cookie 更新、退出清理和启动恢复统一经过应用级 `SessionCommitCoordinator`：

- Coordinator 使用单一异步互斥锁/提交队列，以上操作不得绕过它直接修改 SessionStorage 或发布内存状态。
- 退出/换号意图入队时可以立即推进仅用于拒绝旧请求的内存目标代次，并将会话标记为 transitioning；认证快照与持久化结果仍只能由持有提交权的操作发布。
- 每个操作带有捕获的会话代次和单调递增的 commit ID；获得提交权后立即校验，持锁完成安全存储读写，再校验仍是当前提交，最后才发布内存快照。
- 用户在旧写入等待期间发起退出或登录 B 时，新意图按顺序进入同一队列并推进目标代次；API 在对应提交完成前不得向 UI 报告退出或换号成功。
- 旧提交完成后不得自行无条件删除作为补偿。后继退出/B 登录操作只能在同一队列中按自己的 commit ID 写入，避免旧操作删除新账号数据。
- 持久化失败时不发布与磁盘不一致的“已登录”状态；清理失败进入明确的存储错误/未验证状态，并阻止继续使用旧凭据。
- 恢复读取也在同一队列中执行；只有读取、解析、Cookie 校验和对应代次仍有效时才发布恢复结果。

- Android 使用加密存储并关闭系统备份。
- iOS 使用 Keychain，禁用同步，选择仅本机可用的 Accessibility 配置。
- 永不保存密码。
- 切换账号或退出先使旧请求代次失效。
- 只有当前有效会话的响应出现 `-1001` 或 401，才能清理当前会话；A 账号旧请求迟到时不得退出已经切换到的 B 账号。
- 只有当前有效会话的普通响应可以更新 Cookie；旧会话响应和已经脱离当前状态的退出响应不能写入或删除新账号 Cookie。
- 登录请求使用隔离 Cookie 容器或手工暂存 `Set-Cookie`，验证业务正文、账号身份与安全持久化都成功后一次性提交；失败或取消不污染当前 Cookie。
- 退出先在本地推进会话代次并清理当前状态，再携带已分离的旧 Cookie 尽力通知服务端；其迟到响应无权修改后续会话。
- 网络失败可以保留加密会话，但状态只能是未验证，不冒充已登录。

Cookie 的唯一权威是自有 `SessionStore` 与受控 Dio Interceptor。首版不直接挂载会自动保存所有响应 Cookie 的通用 `dio_cookie_manager.CookieManager`；若后续采用它，必须包在隔离 Jar 后面并证明登录暂存、会话代次检查和退出隔离不会被其自动写入绕过。`PersistCookieJar` 也不能取代加密 SessionStorage。

参考：

- [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage)
- [`FlutterSecureStorage.write`](https://pub.dev/documentation/flutter_secure_storage/latest/flutter_secure_storage/FlutterSecureStorage/write.html)
- [`dio_cookie_manager`](https://pub.dev/packages/dio_cookie_manager)

### 6.5 收藏状态一致性契约

收藏状态由应用级 `CollectionRepository` 作为单一权威，迁移 Android 基线中的账号代次、`writeVersion`、列表 `collect` 和 `collectionSession` 规则。页面不得各自维护第二份可写收藏状态。

#### 普通列表读取

1. 请求发出前同时捕获 `SessionRequest` 和 `writeVersion`。
2. 响应返回后先检查取消，再检查会话仍有效且写版本未变化；只有全部合格，列表返回的 `collect` 才能合入账号缓存。
3. 读取不推进 `writeVersion`。缓存中正在写入或已有较新事实的目标优先，旧列表值不得覆盖。
4. 返回给页面的 Article 使用仓储已知状态覆盖 DTO 值；只有状态已被当前会话接受时，才附加进程内的 `collectionSession` 标记。
5. 切号、退出、进程重启后的旧 `collectionSession` 失效，不能作为当前账号事实。

#### 阅读页显示

- 阅读页打开时不自动扫描收藏列表，也不把路由携带的旧值主动写回仓储。
- 当前账号仓储中有已知状态时始终优先；否则只有路由 `collect` 携带的 `collectionSession` 与当前会话版本键一致时，才作为本次展示的回退值。
- 游客在状态未知时显示“收藏”；点击只引导登录，登录成功后不自动重放本次写操作。
- 已登录但缓存和有效路由提示都不可用时，同样显示用户可理解的目标动作“收藏”，不能出现“确认收藏状态”。用户点击表示“确保已收藏”：仓储先在本次显式操作内核对当前状态；核对失败则停止、不发写请求并提示；核对为未收藏才执行收藏，核对为已收藏则按目标已达成返回成功，不能简单把核对出的最新状态取反。
- 已知为已收藏时显示“取消收藏”，点击表示“确保未收藏”，同样按用户点击时表达的目标执行。超时/取消进入未知后，后续显式操作重新遵守上述核对规则。
- 网页导航到与初始文章不同的页面后，原文章 ID、收藏记录 ID 和 `collect` 提示全部停止使用，避免收藏错页。

#### 写操作与目标身份

- 收藏列表对当前仍有效的记录执行取消时，可以使用该行的 `recordId`，并同时携带服务端要求的原文 ID。
- 内部文章阅读页无论从首页、搜索、专题还是收藏列表进入，收藏和取消收藏始终只按原文 `articleId` 操作；构造阅读目标时必须丢弃路由携带的 `recordId`，防止取消后重新收藏产生新记录 ID 而继续使用旧 ID。
- 没有有效原文 ID 的外部收藏只能在当前收藏记录仍有效时依赖 `recordId` 取消。取消后阅读页不支持重新新增收藏，操作入口隐藏或禁用并解释限制。
- 外部文章没有可收藏的原文 ID 时不得发起“新增收藏”。
- 每次实际写请求开始前推进一次 `writeVersion`，完成（成功、确定失败、取消或不确定）后再推进一次，使写入期间或写入之前发出的读取结果全部失效。
- 同一目标写入期间串行化并暴露 busy 状态；不做乐观成功，不自动重放写操作。

#### 超时、断线与取消

- 在请求尚未发出前取消，可以保持原状态。
- 请求发出后发生超时、连接中断、响应解析失败或调用方取消，服务器可能已经提交；目标状态标记为未知并使用只读收藏列表核对，不能直接回滚后宣称失败，也不能盲目重试同一写操作。
- 核对必须绑定原会话与写版本；有界扫描未找到且尚未到列表末页时仍是未知，只有扫描到末页才能确认“不在收藏中”。
- 页面退出可以停止等待，但仓储必须完成必要的版本推进和状态收尾；后续页面通过仓储事实获得最终结果。

迁移验收至少覆盖：写前列表请求迟到、写入期间列表请求迟到、同账号写后旧 `collect`、切换账号后旧响应、路由提示与缓存冲突、进程重启提示失效、未知状态下按目标操作、内部阅读页丢弃旧 `recordId`、原文/记录/外部收藏三种目标、取消后重新收藏再取消、确定失败、成功、超时后核对、取消后核对和重复点击。对应 Android 证据来自 `CollectionRepository.kt`、`ArticleScreen.kt`、`CollectionRepositoryTest.kt`、`ArticleRepositoryTest.kt` 和 `ProtectedNavigationTest.kt`，Flutter 实现必须逐项建立等价测试，而不是只测试最终布尔值。

## 7. 导航、传参和返回结果

使用 `MaterialApp.router`、`go_router` 和类型安全 Route：

- 三个主入口使用 `StatefulShellRoute`，分别保留首页、专题和我的页面状态。
- 路由层只表达导航和参数，不执行页面业务。
- 必须恢复的数据写入类型安全路径参数或查询参数。
- 大对象不在页面之间传递，只传文章 ID、URL、标题、收藏记录 ID 等稳定标量。
- `extra` 只能作为临时性能优化，不能成为进程恢复后的唯一数据来源。
- 临时子页面结果可以使用 `context.push<T>()` 返回的 Future。
- 收藏变化、会话状态等跨页面事实由 Repository 单一数据源发布，不使用全局结果事件总线。

参考：

- [Flutter 导航指南](https://docs.flutter.dev/ui/navigation)
- [`go_router`](https://pub.dev/packages/go_router)

### 7.1 过期导航和重复点击

Android 版 Host token 不机械复制，因为 Flutter 旋转屏幕不会重建整个 Flutter Engine，但需要保留相同语义：

- 导航门面在每次 push 前生成 `routeInstanceId` 并把它作为可恢复路由状态的一部分；恢复同一栈条目时复用该 ID，新 push 才生成新 ID。每个 Shell branch 另有身份，每次 Router/导航宿主重建产生新的 `navigationEpoch`。页面拿到的导航入口在创建回调时捕获这三者，执行时不能临时读取新值补齐。
- 异步回调跳转前检查 `context.mounted`，但 mounted 只是必要条件；还要同时验证导航 epoch、活动 Shell 分支、来源路由实例仍有效、来源位于其分支栈顶且未被全屏路由或对话框覆盖。
- `StatefulShellRoute` 中仍存活但已不可见的首页、专题或我的页面不得因旧回调发起普通导航。
- 导航入口只对“一次尚未完成的导航尝试”做 single-flight/互斥，拒绝该尝试期间来自同一来源的重复点击。尝试被拒绝或完成后释放互斥；成功进入目标页时来源因不再位于栈顶自然不可导航，返回原页面并重新成为有效栈顶后必须允许新的点击，不能把保留的页面实例永久标记为已消费。
- 已销毁页面产生的回调不得导航。
- 不缓存 Host 未准备时的普通点击命令。

测试至少覆盖：双击文章只入栈一次；切换分支后旧页面回调被拒绝；页面被详情或对话框覆盖后回调被拒绝；Router 重建后旧回调被拒绝；两个相同参数的文章实例保持不同身份；返回后新页面回调仍可正常导航。

### 7.2 登录回跳

- 只保存白名单内的类型化待跳转目标。
- 登录成功后回到收藏页或原文章页。
- 不保存或自动重放收藏/取消收藏等写操作。
- 来源页面已经失效或账号身份变化时丢弃待跳转目标。

### 7.3 路由与状态恢复边界

可序列化参数只是恢复前提，不等于已经完成进程恢复。实现时必须显式配置并测试：

- `MaterialApp.router` 使用支持 Restoration 的 Router 配置并设置根 restoration scope。
- `GoRouter`、根 Navigator、`StatefulShellRoute` 以及每个 `StatefulShellBranch` 使用稳定且互不重复的 restoration scope ID。
- 可恢复 Page 使用稳定的路由信息重新创建；运行期 `routeInstanceId` 在恢复后的同一栈条目中保持一致，新 push 才生成新 ID。
- 路由栈、当前分支、详情参数属于可恢复状态；Dio 请求、Provider 实例、WebView DOM/完整历史、计时器、Snackbar、展开的左滑操作位只存在内存中，恢复后重新加载或回到安全默认值。
- 搜索已提交查询、专题所选真实分类 ID 可保存为小型可序列化状态；分页游标只有在前置列表内容也能从一致的本地快照恢复并验证连续性时才可恢复。若列表内容未恢复，必须从该接口的初始页重新加载，不能只恢复追加页码而跳过前面的数据；不能把大列表塞入 Restoration 数据。
- Android “Don't keep activities”/进程终止与 iOS 后台终止分别做集成或人工专项验证，记录能够恢复和明确不承诺恢复的范围。

参考：[go_router 状态恢复](https://pub.dev/documentation/go_router/latest/topics/State%20restoration-topic.html)。

## 8. UI、布局和组件封装

### 8.1 设计系统

迁移现有设计 Token：

- 四套配色：墨青绿、石板蓝、暖琥珀、莓果玫瑰。
- 跟随系统、浅色、深色三种模式。
- 字号层级 12sp–32sp。
- 间距 8、12、16、24。
- 圆角 8、12、24。
- Material 3 语义色和完整浅深角色。

Flutter 落点：

```text
ThemeData
├── ColorScheme
├── TextTheme
└── ThemeExtension<WanSpacing / WanShapes>
```

不在业务页面重复写相同字号、间距和色值。

### 8.2 公共组件

第一批公共组件只迁移有真实调用方的能力：

- `AppScaffold`
- `AppTopBar`
- `ArticleCard`
- `NetworkListPage`
- `LoadingContent` / `ErrorContent` / `LoadMoreContent`
- `AppListTile`
- `SwipeRevealActionItem`
- `SettingsSectionLabel`

组件只负责渲染和交互，不持有 Repository 或业务状态。

### 8.3 已确认的页面行为

- 数据模型没有图片字段，不增加图片或图片占位。
- 专题一级分类保留左侧列表。
- 点击一级分类切换真实二级分类集合。
- 二级分类支持点击及横向滑动切换。
- 离开首个二级分类时左栏收起，回到首项时恢复。
- 专题文章卡片不重复展示二级分类。
- 时间位于作者/分享者下方。
- 历史左滑显示红色删除图标，右拉折叠。
- 收藏左滑显示红色取消收藏图标。
- 纵向滚动时已展开的操作位自动收回。
- 删除/取消收藏按钮始终位于背景层，避免拖动过程中创建/销毁造成闪烁。

进入业务开发前，阶段 0 必须把以下已确认行为展开为 Android → Flutter 验收矩阵；没有对应测试或人工验收入口的条目不能标记为已迁移：

| 页面 | 必须保持的产品行为 |
|---|---|
| 首页 | 文章分页与每日一问状态独立；问答轮播只切换现有数据；文章点击携带当次会话可用的 `collect` 提示 |
| 搜索 | 编辑查询时隐藏旧结果，只有提交后才显示新查询结果；刷新期间搜索按钮可用性不被错误改变；推荐词来自 `hotkey/json`；新查询取消并隔离旧请求 |
| 登录 | 手机号提示为“请输入手机号”；密码框获得焦点及提交前校验 trim 后的大陆手机号格式；错误文案为“手机号输入有误，请重新输入”；修改手机号清除旧提示；注册、忘记密码和协议保持明确占位行为，不伪装成功 |
| 专题 | 不增加“全部”；一级分类左栏、真实二级分类点击/横滑和每分类状态隔离；列表到底只结束当前专题分页，不自动切换下一专题 |
| 阅读历史 | 单条左滑红色删除图标点击后直接删除；“全部清空”需要二次确认；数据库通知刷新时保留当前列表并局部更新，不能先清空导致整屏闪烁 |
| 我的收藏 | 左滑取消收藏与历史使用同一手势容器；使用红色取消收藏图标；操作按账号代次和目标身份校验 |
| 主题 | 四套配色和三种模式；保存失败回滚到已持久化值，不误报成功 |

矩阵每项至少记录：Android 来源页面/测试、Flutter 目标页面/测试、自动或人工入口、双端结果、差异理由和未验证范围。该矩阵是阶段 0 的强制交付物，不是阶段 6 才补写的说明。

### 8.4 响应式与无障碍

- 长列表使用 `ListView.builder` 或 Sliver，只创建可见项。
- 使用 `SafeArea` 处理刘海、圆角和系统栏。
- 使用 `LayoutBuilder` 根据可用宽度选择布局。
- 约 600dp 以上可将底部导航适配为 NavigationRail，但手机布局保持当前设计。
- 支持动态字体、VoiceOver/TalkBack、深色和高对比度。
- 触摸目标不小于平台建议尺寸。
- 不用 `Platform.isAndroid` 直接决定业务布局；平台能力通过 Capability/Policy 表达。

参考：

- [Flutter 自适应与响应式设计](https://docs.flutter.dev/ui/adaptive-responsive)
- [SafeArea 与 MediaQuery](https://docs.flutter.dev/ui/adaptive-responsive/safearea-mediaquery)
- [Capabilities 与 Policies](https://docs.flutter.dev/ui/adaptive-responsive/capabilities)

## 9. 阅读器与外部跳转

阅读器使用官方 `webview_flutter`：

- Android 使用系统 WebView。
- iOS 使用 WKWebView。
- WebViewController 由页面 Widget 生命周期持有，不进入 ViewModel。
- 离开页面时释放控制器相关资源。
- 收藏接口可能返回 `/blog/show/<数字>` 相对路径；只在 Mapper 中将符合白名单形状的路径补全为 `https://wanandroid.com/...`，其他相对、HTTP 或未知链接不能猜测性改写。
- “旧加载回调隔离”是阶段 0 待验证能力，不提前假设插件提供请求 ID。`NavigationDelegate` 的完成回调只有 URL，进度回调只有数值；同 URL 连续刷新时，仅比较 URL 或在回调到达时读取当前 `loadGeneration` 都不能证明回调归属。
- 原型优先验证“每次超时后的重试/显式刷新创建新的 WebViewController、NavigationDelegate 与 `browserInstanceId`，旧实例闭包携带旧 token 并被拒绝”的方案；不能为了复用 Controller 而伪造回调代次。普通站内导航能否可靠区分同 URL 的迟到回调也必须记录证据。
- 只有主框架导航失败、TLS 失败、渲染进程异常或主页面超时才能进入整页失败；图片、脚本、字体等子资源失败只做脱敏诊断，不能覆盖已经可读的主页面。
- 主页面确认可用后才写阅读历史；失败页、危险 URL、被拦截外跳和仅有子资源回调不写。重复访问按规范化 URL 更新最近访问时间。
- 加载超时停止当前主页面加载并显示可重试状态。阶段 0 必须自动化或通过受控平台桩复现“第一次加载超时 → 同 URL 重试 → 第一次完成或错误回调迟到”；只有原型能证明旧回调被拒绝后，才可将对应机制冻结为实施契约。若插件层无法可靠区分，保守方案是销毁旧平台 WebView、创建新实例，并且任何身份不明的完成回调都不能清除超时、写历史或恢复收藏目标。
- 顶栏保留返回和三点菜单：刷新、外部打开、收藏/取消收藏。收藏菜单读取第 6.5 节的仓储/路由回退规则。
- 网页跳转到其他文章或站内页面后，若当前 URL 不再与初始文章是同一页面，隐藏或禁用原文章收藏动作；绝不能继续使用原文章 ID 收藏新页面。
- 网页可以返回时先返回网页历史，否则退出阅读页；同时必须与 Android 预测式返回和 iOS 边缘返回手势做原型验证。
- HTTPS 标准端口页面允许应用内打开。
- HTTP、电话、邮件、地图等 Scheme 需要用户确认后外跳。
- 未知 Scheme、文件访问、用户信息 URL 和 TLS 错误一律拒绝或取消。
- 不建立 JavaScript Bridge。
- 不向第三方阅读域名注入 API Cookie 或请求头。
- 深色网页只按平台能力尽力适配，不承诺全部网页一致。

预测式返回不能在手势提交时才临时查询并改变 `canPop`。阅读页需提前维护可观察的 WebView 历史能力，交给 `PopScope`/Router 决定是否由 App 栈返回。`onPopInvokedWithResult` 中必须先判断 `didPop`：为 `true` 表示 Route 已经退出，禁止再执行网页返回；只有 `didPop == false` 且当前网页历史状态仍允许时，才调用网页返回。

Android 系统返回在 `canPop == false` 时仍会报告一次未成功的 pop，但 iOS 的 `CupertinoRouteTransitionMixin` 在该状态下可能根本不识别边缘手势，也不会调用回调。因此 Android 和 iOS 不能直接共用同一假设。阶段 0 原型必须分别决定：网页历史优先时是否接受 iOS 边缘手势降级为顶栏返回，或采用经过验证的其他路由策略。若无法可靠同步历史状态，必须记录平台降级，不能同时宣称“网页优先”“iOS 完整边缘返回”和“Android 完整预测动画”均已完成。

参考：

- [`webview_flutter`](https://pub.dev/packages/webview_flutter)
- [`NavigationDelegate` 回调接口](https://pub.dev/documentation/webview_flutter/latest/webview_flutter/NavigationDelegate-class.html)
- [`url_launcher`](https://pub.dev/documentation/url_launcher/latest/)
- [Flutter Android 预测式返回迁移说明](https://docs.flutter.dev/release/breaking-changes/android-predictive-back)
- [`PopScope` 官方说明](https://api.flutter.dev/flutter/widgets/PopScope-class.html)

当前冻结最低版本为 Android API 24、iOS 15。若要下调任一平台版本，必须变更冻结契约并重新完成专项兼容验证，不能默认降级到停止维护的旧依赖。

## 10. 数据保存

### 10.1 普通偏好

主题、显示模式和少量搜索历史使用 `shared_preferences` 的异步 API，并通过 Storage/Repository 封装：

- Widget 和 ViewModel 不直接操作插件。
- 读取失败安全回退，但保留诊断信息。
- 保存失败回滚 UI，不误报成功。
- 搜索历史最近使用置顶、去重且最多 20 条。

`shared_preferences` 只适合少量基础类型，不用于大量数据或敏感凭据。

参考：[Flutter 键值持久化文档](https://docs.flutter.dev/cookbook/persistence/key-value)。

### 10.2 敏感数据

账号、Cookie 和会话代次由 SessionStorage 包装 `flutter_secure_storage`：

- 禁止明文密码。
- Android 排除备份。
- iOS 禁止 Keychain 同步。
- 登出优先清理本机状态，再尝试服务端退出。

### 10.3 结构化数据

阅读历史和离线正文使用 Drift/SQLite：

- 阅读历史与离线正文分表。
- 历史存在不代表正文已缓存。
- 阅读历史按 URL 规范化后去重，最近访问置顶。
- 支持分页查询、按需读取正文、单条删除和全部清空。
- Schema 变化必须提供 Migration 和迁移测试。
- 不使用破坏性迁移兜底。

参考：[Drift](https://pub.dev/packages/drift)。

## 11. 权限获取与封装

当前已实现范围不需要通用运行时权限：

- 网络只需 Android Manifest 的 INTERNET 声明，不弹授权框。
- 应用私有目录和 SQLite 不需要存储权限。
- WebView 不需要额外运行时权限。
- 打开外部应用属于用户确认，不是系统权限申请。

因此第一阶段不引入 `permission_handler`，避免产生无人使用的公共抽象。

以后增加相机、定位、通知等真实功能时，按以下调用链接入：

```text
Feature
  → PermissionPolicy
    → PermissionGateway
      → permission_handler
```

UI 只接触 `granted`、`denied`、`permanentlyDenied`、`restricted` 等业务状态，不直接调用插件。Android Manifest 和 iOS Info.plist 只声明真实使用的最小权限，并在请求系统权限前展示业务理由。

参考：[permission_handler](https://pub.dev/documentation/permission_handler/latest/)。

## 12. Android 与 iOS 适配策略

采用“品牌视觉一致，系统行为适配”：

- 配色、卡片、列表和排版两端一致。
- iOS 保留系统返回手势、键盘行为和合适的页面转场。
- Android 支持系统返回；预测式返回是否能与 WebView 网页历史同时完整工作，以阶段 0 原型结果为准。
- 对话框、选择器等可使用 Adaptive 组件。
- 不复制两套完整页面。
- Android 禁止明文网络流量，不添加不必要的 Network Security 例外。
- iOS 不添加任意网络 ATS 例外。
- 系统栏颜色、图标明暗和页面主题同步。
- 横向专题 PageView、列表左滑操作和 iOS 边缘返回手势必须做冲突测试。

冻结最低版本：

- Android API 24。
- iOS 15。

本机已检测到 Flutter、Dart、CocoaPods 和 Xcode，但正式开始前需要完成：

1. 接受 Xcode License。
2. 重新运行 `flutter doctor -v`。
3. 确认 Flutter stable 版本并提交版本约束和 `pubspec.lock`。
4. 验证 Android SDK、CocoaPods、iOS Simulator 和签名环境。
5. 完整依赖已在阶段0验证并冻结为Android API24/iOS15；后续依赖变更必须重新核对最低版本和双端构建。

## 13. 测试与 CI

Flutter 官方建议大量单元测试和 Widget 测试，并使用少量集成测试覆盖关键流程。

### 13.1 测试分层

- Service：固定 JSON，验证错误码缺失、无 data、`-1001` 和异常字段。
- Repository：DTO 转换、会话代次、账号隔离和写入结果不确定。
- Session：A 请求迟到 401/`Set-Cookie` 不影响 B、登录 Cookie 验证后提交、退出响应隔离、恢复会话验证失败；安全存储写入被人为延迟期间退出或登录 B，等待提交队列完成后同时核对内存状态与重新创建 SessionStore 后的磁盘恢复结果。
- Collection：第 6.5 节的 `writeVersion`、`collect`、`collectionSession`、三种目标身份、取消/超时核对和跨页面单一事实源。
- ViewModel：取消、旧结果隔离、刷新、追加、失败重试和状态回滚。
- PagingController：第 0/1 页、去重、连续无新增暂停和手动继续。
- Widget：加载、空、错误、深色、大字体、专题切换和列表滑动。
- Integration：Android/iOS 登录、专题、阅读、历史、收藏和主题恢复。
- Navigation：隐藏 Shell 分支旧回调、覆盖关系、重复点击、相同参数不同实例和 Router/进程恢复。
- Reader：主框架与子资源失败区分、相对博客链接、首次超时后同 URL 重试并注入首次加载迟到回调、历史写入、三点菜单、URL 变化后的收藏保护，以及 Android/iOS 分平台返回手势。
- Database：Migration、事务、重开持久化及历史/正文分表。

普通 `integration_test` 无法完整操作原生权限弹窗或 WebView 内部内容；这些场景按需要使用 Patrol、原生 XCTest/Espresso 或人工专项验证。

参考：[Flutter 测试策略](https://docs.flutter.dev/testing/overview)。

### 13.2 建议检查入口

```bash
dart format --output=none --set-exit-if-changed .
dart run tool/verify_architecture.dart
flutter analyze
flutter test --coverage
flutter build apk --debug
flutter build ios --simulator --no-codesign
```

涉及代码生成时增加生成结果一致性检查，确保 Freezed、JSON、Drift 和类型安全路由文件没有遗漏更新。

设备流程不是构建成功的同义词。具备 Android Emulator 和 iOS Simulator 的执行环境还必须分别运行：

```bash
flutter test integration_test -d <android-device-id>
flutter test integration_test -d <ios-simulator-id>
```

所有自动化网络与账号测试只使用 Fake、拦截器或固定虚构响应，不访问真实账号、不执行真实收藏写入。真实账号/真机验收单独执行并记录设备、系统、账号类型、操作范围和结果，不能混入 CI。

CI 建议：

- Linux Runner：架构检查、格式、Analyze、单测、Widget 测试、Android Debug 构建。
- Android 设备 Runner：固定 API 的 Emulator 集成测试，覆盖手势、返回、WebView 壳和进程恢复专项。
- macOS Runner：iOS Simulator 无签名构建和 iOS 集成测试。
- 固定 Flutter stable 版本，不使用浮动环境。
- PR 必需检查与本地统一入口一致。
- 当前阶段完整门禁只在包含非Markdown变更的PR执行，纯文档PR及合并后的`main`不重复消耗双端构建；同一PR的新提交取消旧运行。
- 代码生成及生成物一致性在Analyze任务集中执行一次；平台构建直接消费仓库内已提交生成物，缺失时仍由编译或集中diff门禁失败。
- Android设备流程由单一阶段入口在一次安装/调试连接中连续注册，避免按文件重复启动应用；Gradle使用开源Basic缓存，固定API/架构的AVD使用快照缓存。PR #4远端单入口2/2通过并保存首次AVD快照；该PR作用域缓存不自动供下一PR读取。缓存未命中不改变测试内容，后续命中耗时仍须以实际运行记录为准。
- 发布候选额外执行 Android Release/App Bundle、混淆与签名配置检查，以及 iOS 真机、Release/Archive、Entitlements、Keychain 和隐私清单检查；未配置正式签名时明确记录为未验证，不能用 Simulator 构建代替。

## 14. 分阶段实施

### 阶段 0：基线冻结与关键能力验证

- 固定 Android 参考提交和 Flutter SDK 版本。
- 列出所有页面、接口、存储键、数据库表和状态契约。
- 建立第 8.3 节要求的 Android → Flutter 行为与验收矩阵，并为每项关联来源和验证入口。
- 确认包名、应用名、平台最低版本和是否迁移旧数据。
- 使用最小原型验证 WebView 主框架判断与返回历史、Android 预测式返回、iOS 边缘返回、Cookie 隔离、go_router Shell/Branch 状态恢复和隐藏分支导航拒绝。
- WebView 原型必须复现“首次加载超时 → 同 URL 重试 → 首次加载的完成/错误回调迟到”，记录回调身份来源、Controller 是否重建、旧回调拒绝证据和无法可靠区分时的保守降级。原型通过前，加载代次隔离保持“待验证”，不得标记为已解决。
- 锁定会话、收藏、取消、Provider 生命周期、导航和阅读器契约；原型不接真实账号或真实收藏写操作。

交付：冻结的架构文档、依赖清单、完整页面/验收矩阵、难点原型报告和未解决风险。以上交付全部完成后才能进入业务开发。

### 阶段 1：工程骨架与设计系统

- 创建独立 Flutter 工程。
- 建立目录、架构检查、Lint、主题和 CI。
- 实现 AppScaffold、AppTopBar、ArticleCard 等基础 UI。
- 使用 Fake 数据完成一个首页垂直切片。

交付：Android/iOS 均可运行的壳工程和真实页面调用方。

2026-09-18回填：正式工程、架构/阶段检查、Lint/CI、设计系统、基础组件真实调用方、Fake首页和非活动分支栈恢复修正已经落地；Analyze、15例测试、Android/iOS导航恢复Integration、双端Debug构建及模拟器启动均通过，阶段1交付完成。PR #1已合并，远端`main` CI全部通过；用户已明确授权进入阶段2。具体证据以状态记录第2.1节和矩阵第22节为准。

### 阶段 2：网络、分页、首页和搜索

- 实现 DataResult、DataError 和 WanResponse 映射。
- 接入 Dio Service、Repository 和取消机制。
- 迁移 PagingController 契约。
- 首页、每日一问和搜索接入真实接口。
- 实现并验证 Provider 生命周期、应用前后台与 Tab 可见性策略。

交付：成功、空、失败、取消、竞争和分页测试。

2026-09-19回填：已实现严格Result/Wan响应映射、项目取消契约与Dio桥接、公共分页、生产只读首页/问答/搜索/热词、搜索历史有序写入及首页可见性策略；移除生产Fake首页。固定响应与状态机测试覆盖成功、空、失败、取消、刷新/换词竞争、去重、暂停及前后台取消/恢复；最终36/36测试、固定数据双端完整Integration各2/2及Android/iOS Debug构建通过。PR #2已合并为`206c60b4207fd203752d088ac3d6743fd8c123a7`，远端运行35366543999全部通过。按项目网络测试边界，正式生产组合根设备启动未执行；此段记录阶段2完成时点，当前阶段以状态记录为准。

### 阶段 3：专题

- 接入一级/二级分类。
- 实现点击和横滑切换。
- 分类 ID 独立分页、滚动和请求状态。
- 实现左栏收起/展开动画和手势冲突测试。

交付：专题完整行为和 Android/iOS Widget/Integration 测试。

2026-09-19实施回填：正式组合根接入公开只读专题树及真实二级分类文章；分类独立分页/滚动、隐藏取消与8类有界缓存、92dp左栏及320ms位移/淡出已落地。固定数据仓储、状态和Widget覆盖成功/空/失败/重试、取消/迟到、快速切换、动画中间帧、暗色和200%字体；最终51/51 Unit/Widget、Android/iOS单入口Integration各3/3通过。实际公开服务端到端、Android→Flutter逐页视觉对照、真机及远端CI均未执行；阶段4～6能力不因本阶段实现而提前关闭。当前阶段/验收状态以状态记录为准。

2026-09-19合并回填：[PR #6](https://github.com/NAH4E5553/WanAndroid-Flutter/pull/6)的Analyze/Test、Android Integration、Android APK和iOS Simulator远端四项均通过并squash合并。用户报告真机验收完成，但设备、系统、平台和逐项场景尚无记录；实际公开服务端到端、固定Android→Flutter逐页视觉、双端真机细项及阶段6发布门禁仍待独立证据。上段“未执行远端CI”为本地实施时点的历史记录。

### 阶段 4：阅读器与历史

- 接入 WebView 生命周期、URL Policy、相对博客链接和外跳确认。
- 区分主框架与子资源失败，接通加载代次、超时、三点菜单和历史写入条件。
- 接入阅读历史数据库、去重、分页、单条左滑删除与全部清空确认。
- 验证网页返回优先、预测式/边缘返回降级、进程恢复和 API Cookie 隔离。

交付：Android/iOS 阅读器专项、手势冲突和数据库测试。此阶段收藏菜单可以使用 Fake 接口验证展示与目标失效，但不提前实现账号写入。

### 阶段 5：登录、收藏、主题和我的

- 接入主题持久化和失败回滚。
- 实现安全会话、Cookie 权威、登录恢复、退出和登录回跳。
- 完整实现第 6.5 节收藏状态契约，并接入收藏列表、首页/搜索/专题/阅读器收藏和取消收藏。
- 历史与收藏复用同一左滑容器，但保留不同业务动作与确认规则。

交付：会话竞争、Cookie 隔离、收藏写版本、结果不确定、阅读器真实生产入口和跨页面同步测试。

### 阶段 6：完整验收

- 逐页对照 Android 基线。
- 验证浅色、深色、大字体、Insets、横竖屏和无障碍。
- 验证弱网、无网、慢响应、进程终止和账号切换。
- 记录真机设备、系统版本和未验证范围。
- 执行 Android/iOS 设备集成测试及第 13.2 节发布候选检查；真实账号验收与 Fake 自动化结果分开记录。

离线正文缓存继续作为独立后续阶段，不在迁移过程中顺便实现。

## 15. 新增列表页面的标准开发方式

新增一个列表页面时，业务开发只需要：

1. 定义 DTO 和 Domain Model 映射。
2. 在 Service/DataSource 添加接口。
3. 在 Repository 返回 `DataResult<PageResult<T>>`。
4. 配置初始页码、稳定 Key 和请求函数。
5. ViewModel 组合 `PagingController` 状态和页面专属状态。
6. Screen 调用 `NetworkListPage` 渲染业务 Item。
7. 注册类型安全 Route。

以下能力由公共层完成，不允许页面重复实现：

- 初次、刷新和追加状态。
- 请求取消和旧结果隔离。
- 页码推进。
- 去重和同 ID 数据更新。
- 连续无新增暂停与手动继续。
- 接近底部加载触发。
- 通用空状态、错误状态和分阶段重试。
- 页面退出后的资源释放。

## 16. 已冻结决策

2026-09-18用户完整接受报告15.3推荐值，以下决定已冻结：

1. 新 Flutter 版使用独立目录和独立 Git 仓库：`/Users/sn/Desktop/workplace/wanandroid-flutter`。
2. 第一目标对齐 Android `78cdaad` 已实现功能，不提前实现离线正文缓存。
3. 使用 Riverpod，不用 ChangeNotifier 作为全项目状态方案。
4. Android 最低 API 24，iOS 最低版本 15。
5. UI 保持当前品牌设计，只适配平台手势、转场、系统控件和 Insets。
6. 使用新的应用 ID，让 Android 原版和 Flutter 版可以同时安装。
7. 首版只支持 Android 和 iOS，不同时支持 Web 与桌面端。
8. 不迁移 Android 原版设备上已经持久化的主题、Room 数据和登录 Cookie；Flutter 版仍需迁移等价行为、数据模型和兼容契约。

第 6、8 项的历史取舍说明保留如下：

- 如果 Flutter 版是独立应用，新包名最简单，也最安全。
- 如果 Flutter 版要覆盖现有 Android 应用，就必须保持原包名、签名，并为 Room、DataStore、Keystore 会话和安装升级设计专门迁移方案。这会显著扩大工作量和发布风险。

上述决定已经确认，允许进入阶段1创建正式工程；仍不接真实账号，也不提前实现阶段2～6业务。
