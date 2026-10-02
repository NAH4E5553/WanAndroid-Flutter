# 启动耗时统计开工单

## 1. 范围与授权

- CONTRACT-ID：STARTUP-01
- 类型：普通诊断任务；不新增平台通道、权限、持久化、依赖或产品行为，不修改会话/头像恢复语义。
- 当前阶段：阶段5既有主应用的专项测量，不启动阶段6完整验收。
- 授权：2026-10-01用户要求统计桌面Launcher到主应用首页展示耗时并判断是否需优化。
- 目标：默认关闭的本地启动分段埋点、固定数据回归、获授权后的公开只读接口设备采样。
- 非目标：上传分析数据、登录/收藏操作、更改启动或首页UI、直接实施优化、发布验收。
- 产品选择：无。真实网络重复测量单独等待用户确认；不读取或打印账号、Cookie、文章内容。
- 高风险项：无；复用Flutter已有帧统计API，仅观察时间，不新增平台业务能力或改变原生生命周期。

## 2. Android 行为基线

固定提交：`78cdaade84ef24ebbe825041b499cbe1cd7ee286`。

| 项目 | 来源 | 已确认行为 |
|---|---|---|
| 入口 | app/src/main/java/com/personal/wanandroid/MainActivity.kt | onCreate组装主题和AppNavigation |
| 首页 | feature/home/src/main/java/com/personal/wanandroid/feature/home/view/HomeScreen.kt | 文章/问答独立展示；本任务保持UI-02 |
| 状态/接口 | feature/home/src/main/java/com/personal/wanandroid/feature/home/viewmodel/HomeViewModel.kt；既有行为矩阵T04 | 文章与问答独立请求；不增加接口 |

有意差异：Flutter新增本地诊断，用户已请求；界面/数据契约无差异。

## 3. Flutter 生产调用链

| 层 | 文件 | 职责 |
|---|---|---|
| 入口/组合根 | lib/main.dart；app/bootstrap/bootstrap.dart | 启动时钟、依赖组装及首帧测点 |
| View | features/home/view/home_screen.dart | 按当前UiState发送帧构建事件 |
| ViewModel | features/home/view_model/home_view_model.dart | 将本页不可变快照分类为loading/success/empty/error |
| Repository/DataSource | 既有ArticleRepository及ArticleNetworkDataSource | 保持生产事实源和接口不变 |
| 诊断 | core/diagnostics/startup_metrics.dart | 一次启动的单调时钟和去重测点；帧时间对应rasterFinish |

复用既有UiState、可见性、分页代次及Flutter FrameTiming。不建第二套业务状态。

## 4. 状态、身份与并发

| 事实 | 权威 | 身份/版本 | 持久化 |
|---|---|---|---|
| 首次文章/问答状态 | HomeViewModel的HomeUiState | 当前页面快照及datasetGeneration | 无 |
| 一次启动的耗时 | StartupMetrics | 进程内单次main；测点一次；单调微秒 | 无，诊断日志由主机保存到忽略build目录 |

仅当前可见且仍有效的快照能完成帧测点；dispose/旧快照/不可见不记。失败记录error终态，不冒充成功；空内容单列empty。后续刷新、路由重进不覆盖首次测点。未完成的测点保持缺失，不推算成功。

## 5. API/平台契约

不新增业务API/原生能力。复用Flutter首帧栅格化Future及FrameTiming；桌面点击/系统启动时间从主机ADB本地观察，应用内Dart时钟不冒充Launcher起点。诊断由`STARTUP_METRICS=true`编译开关开启，默认关闭；不上传数据。系统屏幕实际呈现/显示扫描比rasterFinish更晚，本统计不声称测到屏幕发光。

## 6. 行为矩阵与UI

- 加载圈：只完成首帧，不完成内容展示。
- 文章成功、问答仍加载：完成文章测点，完整首页保持缺失。
- 两块成功或空：分别记录状态，在对应帧栅格化后完成首页测点。
- 错误：完成失败终态，不产生首页成功测点。
- 不可见/旧帧/重复帧/刷新：不冒充首次成功、不重复输出。
- UI：保持现状；没有视觉改动，不新增视觉验收结论。

## 7. 验证计划

最小回归必须拦截“loading算首页完成”“错误算成功”“只等文章忽略问答”“旧帧/隐藏帧算完成”“批量回调时间当栅格化时间”。Unit验证单调时钟/去重/帧选择，Widget或ViewModel固定数据验证终态分类及独立请求。不使用真实账号做自动回归。

运行统一本地门禁、定向测试、Android Profile构建和专项桌面冷启动；适用的双端集成/构建据实际设备执行。未运行项如实记录。样本分列冷启动/热返回、首帧/文章/完整首页、真实网络/固定数据、Profile/Debug；不混算。

## 8. 开工结论

现有生产调用方、唯一状态源、身份语义和错误拦截测试均明确；可以实施诊断。无实现偏差时交付明确写“无”。真实网络重复采样另待本轮授权；不授权时只测固定数据，不外推真实首页时间。

## 9. 执行补充（2026-10-01）

用户后续回复“确认”，本轮5次真实公开只读采样授权已收到。原包保留数据的采样被自动审批拒绝，因为可能携带已有会话Cookie；采用不复制数据/禁用备份/首次安装的独立游客包作为更安全的测量载体，只修改applicationId与桌面名称，生产Dart逐字一致且锁版本/校验一致。没有改变会话或业务源码。实际测量5/5成功，临时包已卸载。

测量实现偏差：安装身份为同源码独立游客包；不能冒充原安装带账号/偏好状态或发布验收。原开工单的目标、非目标和原定测试计划保留，结果与限制见[统计记录](../reports/启动耗时统计记录.md)。
