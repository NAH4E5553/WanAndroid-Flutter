# 用户头像本地功能开工单

配套文档：[用户头像本地功能需求](../用户头像本地功能需求.md)、[用户头像本地功能UI设计](../用户头像本地功能UI设计.md)（已确认）、[UI-08 行为矩阵](../阶段0行为对照矩阵.md)

## 1. 范围与授权

- CONTRACT-ID：`FEATURE-AVATAR-LOCAL`
- 任务类型：高风险功能（权限/平台能力 + 新依赖 + 本地持久化 + 跨页/跨账号状态）
- 当前阶段：阶段 5 已交付（PR #11/#12/#13/#14/#17 合并）；阶段 6 未授权、未启动
- 用户授权或既有冻结依据：2026-09-26 用户确认产品需求；2026-09-27 UI 设计稿两轮评审定稿；2026-09-27 负责人以《用户头像本地功能最终实施方案》确认本开工单并授权编码（方案 A 原生相册通道、image_picker+path_provider、PNG 输出、accountVersionKey、进程恢复）
- 功能目标：已登录且会话已验证的用户可将系统拍照或相册单选图片经 1:1 调整确认后作为本机当前账号头像；独立查看页支持缩放查看与"保存到手机"；默认头像为 Android 基线人物徽标；按 `userId` 本机隔离、退出保留、不上传不同步；不提供删除/恢复默认
- 明确非目标：服务端头像上传/下载/同步；头像 URL 与网络图片；游客编辑；昵称等资料编辑；视频/GIF/Live Photo；自建相机或相册页；恢复默认/删除；拍照原图自动入库；离线缓存、注册、找回密码、发布能力
- 需要确认的产品选择：见 §9 待确认清单（依赖与相册写入通道）

高风险条件（全部命中，编码前需项目负责人确认开工单）：

- [x] 权限、相机、相册、文件或其他平台能力
- [x] 数据库、偏好、安全存储或迁移（新增本机文件持久化与索引）
- [x] 跨页面、跨账号、跨进程状态
- [x] 新依赖、发布配置、签名、CI 或安全门禁

## 2. Android 行为基线

固定基线提交：`78cdaade84ef24ebbe825041b499cbe1cd7ee286`

| 项目 | 来源文件/测试 | 已确认行为 |
|---|---|---|
| 页面或入口 | `feature/profile/.../view/ProfileScreen.kt`、`ProfileAccountTest.kt`、`ProfileViewModelTest.kt` | 56dp `primaryContainer` 圆形 Surface + 28dp `ic_person` 描边图标（`onPrimaryContainer`）；无查看/拍照/选图/保存能力 |
| ViewModel/状态 | `ProfileViewModel.kt` | 会话状态驱动账户区；无头像状态 |
| Repository | 不适用 | Android 基线无头像仓储 |
| Service/API | 不适用 | 无任何头像接口（WanAndroid 服务端无此能力） |
| Android 测试 | `ProfileAccountTest.kt` | 账户区布局与状态展示 |

Flutter 与 Android 的有意差异及确认依据：本功能是 2026-09-26 用户明确批准的 Flutter 新增产品能力，不是基线迁移；默认头像徽标（尺寸、颜色角色、矢量路径）严格复刻基线 `ic_person`，其余查看页/弹框/调整页均为新增界面，按已确认设计稿实现。依据：需求文档 §1/§2、矩阵 UI-08 行、状态记录 2.5 节"用户头像本地功能"行。

## 3. Flutter 生产调用链

| 层级 | 文件或计划落点 | 职责 |
|---|---|---|
| Route/Navigation | `app/router/app_routes.dart`（Profile 分支新增 `avatar`、`avatar/adjust` 两个 TypedGoRoute，重新生成 `app_routes.g.dart`）；`features/profile/navigation/` 增加页面工厂 | 只组装依赖和导航；子页位于 Shell 外，不渲染底栏 |
| View | `features/profile/view/profile_screen.dart`（头像区改造）；新增 `avatar_viewer_screen.dart`、`avatar_adjust_screen.dart`；`features/profile/component/` 人物描边图标画笔（基线矢量转换，个人中心/查看页两处调用） | 只消费 UiState 和发送事件；手势状态由 View 捕获并提交给 ViewModel |
| ViewModel | 新增 `avatar_viewer_view_model.dart`、`avatar_adjust_view_model.dart`（路由实例隔离、自动释放）；扩展 `profile_view_model.dart`（头像状态订阅 + 可编辑判定） | 候选/提交编排、busy/失败反馈、代次校验转发 |
| Repository 契约/实现 | 新增 `data/repository/contract/avatar_repository.dart`、`data/repository/implementation/default_avatar_repository.dart` | 唯一头像事实源：按 `userId` 的当前头像索引、候选生命周期、处理管线（解码/方向/裁切/编码/原子替换）、保存到相册单飞 |
| DataSource/Service | 新增文件存储（`data/storage/avatar_file_storage.dart`：索引 JSON 版本化原子写 + 私有目录图片文件）；平台网关（系统拍照/相册选图、相册写入；落点 `data/storage/` 或新 `data/platform/`，实现期按 import 边界定名） | 插件调用只存在于数据边界；测试用 Fake 注入 |
| 生产组合根 | `core/providers.dart`（新增 `avatarRepositoryProvider` 契约 Provider）+ `app/bootstrap/app_dependencies.dart`（装配真实实现）；`AuthStateView` 增量补充 `userId` 字段（`DefaultAuthRepository.view()` 从 `SessionSnapshot.user.id` 填充） | View 只接触接口类型 |

需要复用的现有组件、状态模型、Repository、平台封装：`AuthRepository` 监听/`view()` 模式（AuthStateView 增量扩展）、`SessionStore.generation`、`ThemePreferences` 的"单键版本化原子写 + 读失败安全默认 + 写失败回滚"模式（索引存储照此实现）、`AppTopBar`/`AppScaffold`/`WanSpacing/WanShapes/WanTypography`、go_router 子路由与 `context.push<T>()` 返回结果通道、`stage5_ci_test.dart` 合并集成入口。

不复用现有能力的理由：无。图片选择/相册写入/文件路径能力当前仓库不存在，必须新增（见 §9 确认项）；裁切/编码自行实现，不引入裁切三方库。

## 4. 状态、身份与并发

| 业务事实 | 唯一权威 | 规范身份 | 操作身份 | 账号/会话代次 | 请求/写版本 | 持久化期限 |
|---|---|---|---|---|---|---|
| 各账号当前头像 | `AvatarRepository` + 私有目录 `avatar_index.json`（版本化单值原子写） | 服务端 `userId`（不用昵称/用户名/Cookie） | 存储索引条目（userId → 文件名） | 提交/查看均绑定发起时会话代次 | 索引写入原子替换；版本字段防旧写覆盖 | App 私有目录，退出保留，排除系统备份 |
| 候选图片（本次拍/选） | `AvatarRepository` 内存 + 临时目录文件 | 临时文件路径 | 一次候选会话 | 发起时捕获 generation；返回/提交前校验 | 不入索引 | 临时目录，提交或丢弃后清理 |
| 保存到手机 | 系统 MediaStore/PhotoKit | 内容为当前已生效头像字节，文件名 `wanandroid_avatar_<时间戳>` | 保存动作 busy 单飞 | 读取当前头像前校验代次 | 不改索引 | 系统相册（不覆盖旧文件） |
| 可编辑状态 | `AuthStateView`（会话权威） | `authenticated && 无 loading/unverified/expired/storageNotice` | — | 随会话变化 | — | 会话生命周期 |

- 迟到结果接纳条件：拍照/选图/提交返回时重新校验路由实例仍存在、会话已验证且代次与发起时一致；不一致一律丢弃候选、清理临时文件，不导航、不覆盖、不弹过期提示。
- 取消后的确定状态：调整页取消/系统返回 → 候选丢弃、临时文件删除、索引不变；相机/相册取消 → 同上；弹框取消 → 仅关弹框。
- 失败后的回滚依据：解码失败/超大/编码失败/索引写失败 → 索引保持最后持久化值，旧头像不变，无半成品；读取失败 → 显示默认徽标并保留脱敏诊断。
- 未知写入结果的核对方式：本任务全部为本地写入，不存在"服务端可能已执行"的不可核对态；本地写失败即失败，文件系统写成功但进程随后终止由索引原子替换保证不出现半成品。
- 快速连续操作的最终语义：提交/保存均单飞 busy；重复触发忽略；连续两次提交以最后一次意图为准，先完成的候选被后一次覆盖。
- 切号、退出、离开页面和 dispose 后的处理：切号立即切换到新账号头像或默认徽标（`AuthStateView` 驱动，无旧账号闪现）；退出保留文件但 UI 回默认徽标；子页 ViewModel dispose 丢弃未提交候选并清理临时文件；外部页（相机/相册）期间退出登录 → 返回后代次校验失败，候选丢弃。

## 5. API 或平台契约

无服务端 API。平台能力契约：

| 调用方 | 方法/能力 | 路径或入口 | Path ID | Body/Query | 响应/回调 | 目标身份 |
|---|---|---|---|---|---|---|
| AvatarRepository | 系统拍照（静态图） | `image_picker` → 系统相机 Intent / `UIImagePickerController` | 不适用 | 不适用 | 临时文件路径；取消返回空 | 发起时会话代次 |
| AvatarRepository | 相册单选（静态图，尽量只取选中项临时访问权） | `image_picker` → Android Photo Picker / SAF、iOS PHPicker | 不适用 | 不适用 | 临时文件路径；取消返回空 | 发起时会话代次 |
| AvatarRepository | 保存当前头像到相册 | 平台通道：Android `MediaStore.Images`（API 29+ 免运行时权限；24–28 需 `WRITE_EXTERNAL_STORAGE` 运行时权限，降级单独验证）；iOS `PHPhotoLibrary` 添加-only（`NSPhotoLibraryAddUsageDescription`） | 不适用 | PNG 字节（512×512）+ 毫秒级时间戳文件名（同秒多次保存不覆盖） | 写入成功/权限拒绝/永久拒绝/空间不足/失败 | 不改变应用内头像 |
| AvatarRepository | 私有目录路径 | `path_provider`（应用支持目录，子目录标记排除备份） | 不适用 | 不适用 | 目录路径 | 按 userId 分文件 |

DataSource/Service 级契约测试：平台网关以 Fake 接口注入（临时文件/失败/取消/权限拒绝可脚本化）；索引存储用内存文件系统 Fake 覆盖原子性与失败注入；真实插件不进单元测试。

权限、隐私、日志和平台降级：
- Android 拍照走系统相机 Intent，应用不申请 `CAMERA` 运行时权限（`image_picker` 清单不含 CAMERA）；iOS 需 `NSCameraUsageDescription`，仅在选择"拍照"时触发系统弹窗。
- 相册选择 Android Photo Picker / iOS PHPicker 均无需相册读取权限；不申请 `READ_MEDIA_IMAGES` 或完整相册访问。
- 保存到相册的权限差异按 §7.1 权限矩阵执行；权限首次拒绝给用途反馈，永久拒绝弹"前往设置"，不循环弹窗。
- 头像文件与索引所在目录排除 Android 备份（`dataExtractionRules`/`fullBackupContent`）与 iOS 备份（文件级排除标记，需在平台通道内实现）；错误文案不含本地路径、URI、元数据或堆栈；日志仅码/来源，不含图片内容。
- 新增 Info.plist/Manifest 权限声明仅为上述最小集合。

## 6. 行为矩阵

对应需求文档 AVATAR-01～15 与设计稿第 12 节映射；本表登记自动测试层级：

| 场景 | 预期结果 | 自动测试层级 | 设备/人工验证 |
|---|---|---|---|
| 首次进入（AVATAR-01） | 默认徽标（无首字）；已验证可点进查看页；游客/恢复中/未验证/失效不可点 | Widget（四会话状态 × 浅深色） | 读屏 |
| 查看页（AVATAR-02） | 当前头像展示、返回/横向三点；缩放拖动不触发修改；文件丢失回退默认徽标 | Widget + Repository 单测 | 手势 |
| 底部弹框（AVATAR-03/12） | 固定四项；取消独立置底；无恢复/删除入口；遮罩/返回只关弹框；焦点进入/退出回归 | Widget（含语义） | 读屏 |
| 拍照取消/失败（AVATAR-04） | 回查看页，原头像与索引不变；临时文件清理 | Repository 单测（Fake 网关） | 真机系统相机 |
| 相册取消/失败（AVATAR-05） | 同上 | Repository 单测 | 真机选择器 |
| 调整取消（AVATAR-06） | 候选丢弃，原头像不变；候选在提交前不出现在查看页/个人中心 | Repository + ViewModel + Widget | 手势 |
| 替换成功（AVATAR-07） | 新图完整处理、原子提交后查看页与个人中心同步，重启后仍在；索引版本化 | Repository 单测（含存储重开） | 设备 |
| 替换失败（AVATAR-08） | 解码/超大/编码/索引写失败保留旧头像，无半成品，停留调整页可重试/取消 | Repository 故障注入单测 | — |
| 保存当前头像（AVATAR-09） | 自定义存 512×512 生效副本；默认存徽标渲染透明底 PNG（512）；不含界面内容；成功/权限拒绝/写入失败文案区分；重复保存不覆盖 | Repository 单测 + Widget 文案 | 真机相册 |
| 账号切换（AVATAR-10） | A/B 按 userId 隔离；外部页返回不接纳旧账号候选（代次校验） | Repository 单测（切号注入） | — |
| 退出/重登（AVATAR-11） | 退出回默认徽标且文件保留；同 userId 重登恢复展示 | Repository 单测 | — |
| 无删除能力（AVATAR-12） | 所有页面无恢复默认/删除 | Widget | — |
| 权限（AVATAR-13） | 仅操作时最小权限；拒绝/永久拒绝不改头像；文案按 §7.1 矩阵 | Widget（反馈文案） | 真机权限弹窗（人工） |
| 恢复/迟到结果（AVATAR-14） | 只接纳可证明归属的外部结果；销毁/退出/换号后迟到结果拒绝 | ViewModel/Repository 注入单测 | Android 进程恢复（真机专项） |
| 视觉与无障碍（AVATAR-15） | 四配色 × 浅深、200%、Insets、弹框焦点、读屏、双端返回 | Widget + Golden 就绪 | 逐页视觉/读屏（阶段 6） |

## 7. UI 验证

- [x] 短、长、空内容（Widget：默认徽标/自定义/会话各态文案）
- [x] 窄屏（320/360/390 Widget 断言：不溢出、按钮可达）；横屏为设备人工项（适用、待验证）
- [x] 浅色、深色和四套配色（角色映射见设计稿 §8；Widget 浅深已验，四配色全组合留 Golden/阶段 6）
- [x] 100% 与 200% 字体（Widget：最小高度策略、按钮可达；列表滚动可达）
- [x] Loading、Empty、Error、Busy、Disabled（Widget：处理中进度条、失败/权限反馈、会话禁用）
- [x] 点击/路由/生命周期（Widget：dispose 丢弃候选；捏合缩放/拖动/旋转手势为设备人工项，适用、待验证）
- [x] Tooltip、命中测试和读屏语义（Widget：弹框焦点进入与回归、当前头像语义、48dp 目标；Tab 焦点圈定为实现验收项）
- [x] Android/iOS Insets、系统栏（Widget/代码声明）；真机返回手势与平台差异待设备专项

设计稿、截图或固定基线来源：`docs/用户头像本地功能UI设计稿.html`（已定稿交互评审稿）、`docs/用户头像本地功能UI设计.md`（角色映射与规格）、Android 基线 `ic_person.xml`。

## 8. 验证计划

- 能在错误实现上失败的最小回归：
  - 候选/已生效分离：取消后 `data`（索引）不变的断言（旧实现直接替换索引会失败）；
  - 原子替换：索引写失败注入后旧索引可读且文件无半成品；
  - 代次校验：换号后返回的候选被拒绝（旧实现接纳会失败）；
  - 缩略/提交不污染：仓库提交后其他账号文件与临时目录被清理断言；
  - 单飞：保存到相册进行中重复触发被忽略。
- Unit：AvatarRepository（索引原子写/读失败回退/失败注入/切号/退出保留/重登恢复/保存单飞/默认头像 PNG 渲染）、平台网关 Fake 契约、AuthStateView.userId 扩展回归。
- Widget：个人中心头像四会话状态、查看页两态与语义、弹框四项与焦点、调整页裁切几何（含 320/360/390 宽度、200% 字体）、失败反馈文案。
- Repository/DataSource：索引存储 Fake（内存文件系统）行为测试；网关取消/权限拒绝脚本化测试。
- Integration：`stage5_ci_test.dart` 增加固定 Fake 图片的全流程（查看页 → 弹框 → 调整 → 提交 → 个人中心同步 → 重启恢复），不接真实账号。
- Android：`dart run tool/verify_pr.dart --android`（构建 + 最新阶段集成）；真机专项：真实系统相机/相册/相册写入/权限拒绝/Activity 恢复（人工，单独记录）。
- iOS：`dart run tool/verify_pr.dart --ios`（Simulator 构建 + 集成）；真机权限/相册写入人工专项。
- 人工专项：真机权限弹窗（自动化无法操作原生权限框）、Android 进程终止后外部结果归属、双端系统页返回手势、逐页视觉与读屏（阶段 6 范围的逐项验收另记）。
- 文档和行为矩阵：完成后回填矩阵 UI-08/AVATAR 行、状态记录 2.5 节行、设计稿"实现落点"；PR 引用本开工单与 CONTRACT-ID。
- 暂未验证及原因：真实账号不适用（本功能无服务端交互）；真机权限/系统页专项需设备与人工，编码阶段无法完成时如实标记待验证。

计划运行：

```bash
dart run tool/verify_pr.dart
dart run tool/verify_pr.dart --android
dart run tool/verify_pr.dart --ios
```

设备不唯一时传 `--android-device=<id>` / `--ios-device=<id>`；设备缺失时如实记录环境阻塞。

实际执行（2026-09-27，分支 `codex/avatar-local`，工作树未提交）：

| 入口 | 结果 |
|---|---|
| `dart run tool/verify_pr.dart` | 通过：生成/格式/Analysis Server/架构+敏感数据门禁及夹具/阶段1～5结构/flutter analyze/全量 Unit+Widget 177 例（新增 avatar 仓储 14 + 处理与通道 6 + Widget 10） |
| `--android --android-device=emulator-5554`（Android 12/API31 模拟器） | 通过：基础门禁 + stage5 集成 3/3（含新增头像设备流程：入口→查看页→弹框→拍照→调整→真实原子提交→双处同步）+ Debug APK 构建 |
| `--ios --ios-device=iPhone 16 Pro`（Simulator） | 通过：基础门禁 + stage5 集成 3/3 + iOS Simulator Debug 构建 |

第二轮（审查修复后复跑，2026-09-27）：基础门禁再次通过（全量测试增至 196 例，新增 busy 复位/并发选图/会话失效/超大图/旋转几何像素/导出像素/备份诊断回归）；`--android --android-device=emulator-5554`（模拟器，后被真机取代）通过后，按用户指令改跑真机：`--android --android-device=6578b1b0`（MI 9/Android 11/API30）通过：stage5 集成 4/4（含头像设备流程与 AVATAR-14 进程恢复重归属）+ Debug APK 构建；`--ios --ios-device=iPhone 16 Pro` 通过。第二轮审查修复新增 8 项失败回归（busy 复位、损坏/超大候选、会话失效、并发选图、渲染等待切号、备份诊断），全量测试增至 196 例。

第三轮（Codex接手剩余阻断，2026-09-27）：`dart run tool/verify_pr.dart --android --android-device=6578b1b0`通过：文档60链接、116源码/16架构夹具、297文本/4敏感夹具、阶段1～5、analyze、全量200项Unit/Widget、MI 9/Android 11/API30 stage5集成5/5及Debug APK。新增证据覆盖查看页生产dispose、校验/原生归一/lost-data等待期间切号、pending串行、生产裁切约束、文件/总像素预算、应用重建后由`WanAndroidApp`自动进入调整页，以及Android原生Orientation 6旋转与2镜像像素。当前Swift实现另经`flutter build ios --simulator --debug`编译通过；本轮没有iOS真机，未执行iOS运行时方向/PhotoKit/权限/手势。

实现偏差：根据审查实证与负责人确认，原“只使用dart:ui处理方向”改为原生预归一：Android新增官方AndroidX ExifInterface 1.4.2，iOS使用系统ImageIO；候选在进入调整页前统一转为无EXIF PNG。为防全尺寸解码OOM，新增32MiB编码文件、8192单边与1600万总像素预算，并将调整预览限制为2048解码尺寸。MI 9的AVATAR-14自动证据是“不执行旧App dispose的应用重建+生产导航监听”，不能写成真实OS杀进程。未执行项：Android真实系统相机/相册选择、相册写入/权限拒绝与永久拒绝、真实OS进程终止恢复、返回手势；iOS全部真机项；真实账号隔离；逐页视觉与读屏（阶段6）。

## 9. 开工结论与待确认项

- [x] 没有未解决的身份或状态权威冲突（头像唯一权威 = AvatarRepository；可编辑判定 = AuthStateView）
- [x] 没有跨越当前阶段或用户授权（阶段 5 范围内的新增产品能力，用户 2026-09-26 确认需求）
- [x] 没有未批准的新依赖、权限或产品取舍（2026-09-27 负责人确认最终实施方案）
- [x] 有真实生产调用方（ProfileScreen 与新增两页）
- [x] 测试计划能拦截已知错误模式，而非只证明成功路径
- [x] 可以进入实现（负责人已确认）

### 已确认决定（2026-09-27 负责人《最终实施方案》）

1. **新依赖**：Flutter层为`image_picker`（系统相机/系统选择器）与`path_provider`（私有目录）；EXIF实证失败后按负责人确认方案，Android原生增加官方`androidx.exifinterface:exifinterface:1.4.2`，iOS只用系统ImageIO。未引入`image`、裁切插件、相册保存插件或`permission_handler`。
2. **保存到相册 = 方案 A**：自行实现最小原生平台通道（Android `MediaStore`，API 24–28 用 `maxSdkVersion=28` 的 `WRITE_EXTERNAL_STORAGE` 降级并在保存时申请；iOS PhotoKit `.addOnly`）。
3. **图片处理**：输入 JPEG/PNG/可解码 HEIC/HEIF；临时文件立即复制 → 解码验尺寸 → 应用方向 → 按用户变换重绘 → 1:1 裁切 → 输出 **512×512 PNG**（`dart:ui` 仅有 PNG 编码器）→ 重解码验证 → 原子提交；不保留原图 EXIF/GPS/拍摄时间/设备型号。处理能力在数据/平台边界的 `AvatarImageProcessor`，Repository 契约不暴露 `dart:ui` 类型。必须用带 EXIF 旋转与镜像的夹具验证双端方向归一；任一平台不正确则暂停并重新提交原生归一化方案，不得临时引入图片库。
4. **账号身份**：长期归属 `userId`；操作身份 `userId + accountVersionKey`（opaque，由 `SessionStore.authenticatedVersionKey()` 产生，不含 Cookie/凭据）。`AuthStateView` 增量提供 `userId` 与 `accountVersionKey`；Feature 不得读取 SessionStore/Cookie/原始 generation。
5. **Android 进程恢复**：外部系统页面前持久化唯一 `PendingAvatarOperation`（operationId/userId/source/createdAt/状态）；启动 `retrieveLostData()`；恢复到调整页需同时满足唯一 pending、已验证登录、userId 一致、未超 24 小时、文件存在且可解码；成功/取消/失败/丢弃后清除 pending。进程重启后 accountVersionKey 必变，以"持久化 pending + 已验证同 userId"重建归属。
6. **原子提交 10 步**：唯一临时名 → 写完整 PNG → flush → 重解码验证 → 复核 userId/accountVersionKey/writeVersion → 改名最终文件 → 临时索引写入并 flush → 原子替换索引 → 更新内存并通知 → 尽力清理旧文件/孤儿（清理失败不回滚）。Android 已 `allowBackup="false"`，不新增 dataExtractionRules；iOS 目录经最小原生能力排除备份。
7. **权限矩阵修正**：Android 拍照不声明、不申请应用 `CAMERA` 权限；iOS 选图 `requestFullMetadata: false` 并配置 `NSPhotoLibraryUsageDescription`；同步修正 UI 设计文档旧表述。

负责人确认（高风险功能必填）：用户已确认《用户头像本地功能最终实施方案》并授权编码；任何偏离需重新确认。

确认日期：2026-09-27
