# WanAndroid Flutter CI 与独立审查

## 当前状态

- 确定性 CI 包含架构、敏感数据、阶段1～5结构、Analyze、Unit/Widget、Android/iOS Integration 和双端 Debug 构建。
- 每个 PR 都创建固定名称的分类与文档检查。纯 Markdown PR 的五项 Flutter 重任务在 job 层跳过；包含任何非 Markdown 变更的 PR 运行完整门禁。不得用工作流级路径过滤跳过 Ruleset 必需检查，否则检查会永久 Pending。
- OpenCodeReview 配置已进入源码但默认关闭。`OCR_ENABLED` 未明确设为 `true` 时不调用模型、不产生模型费用，也不会把 Flutter 代码上下文发送到模型服务。
- OCR 是辅助语义审查，不证明代码正确，不替代确定性 CI、真机、视觉、无障碍或人工判断。

## 本地入口

```bash
python3 .github/scripts/verify_docs.py
python3 -m venv build/ci-tools/venv
build/ci-tools/venv/bin/python -m pip install -r .github/tests/requirements.txt
build/ci-tools/venv/bin/python .github/scripts/prepare_ocr_action.py
build/ci-tools/venv/bin/python -m unittest discover -s .github/tests -v
dart --packages=tool/standalone_package_config.json tool/verify_architecture.dart
dart --packages=tool/standalone_package_config.json tool/verify_architecture_fixtures.dart
dart --packages=tool/standalone_package_config.json tool/verify_sensitive_data.dart
dart --packages=tool/standalone_package_config.json tool/verify_sensitive_data_fixtures.dart
```

OCR 准备脚本只下载 Alibaba OpenCodeReview 固定提交的两个公开文件，逐字节校验 SHA-256 后生成适配器。失败时关闭，不回退执行未适配的上游 Action。生成文件只位于已忽略的 `build/ci-tools/ocr-action`。

## OCR 信任边界

- 只处理目标为 `main` 的同仓库、非 Draft PR。
- 工作流检出 PR 的 `base.sha`；适配器、固定哈希和审查规则都来自已受保护的基线。
- PR head 只作为 Git 审查对象，不检出或执行其中的准备脚本。
- 工作流根权限为 `contents: read`；仅审查任务获得 `pull-requests: write` 以发布评论。
- 原始模型结果、stderr 和远端错误正文不进入日志、Artifact 或失败评论；正常代码发现会进入 PR 评论。
- 运行期禁止 OCR CLI 自升级；上游版本、源码提交和哈希固定，升级必须重新审计和回归。
- 外部 Fork 不获得模型 Secret。若未来需要审查任意 Fork，必须改用持有凭据的 GitHub App 或外部检查服务，不能通过 `pull_request_target` 执行 PR 代码。

## 启用前置条件

启用需要用户单独确认 Flutter 代码上下文外发、模型服务和费用边界，然后为本仓库配置独立值：

| 类型 | 名称 |
|---|---|
| Secret | `OCR_LLM_URL` |
| Secret | `OCR_LLM_AUTH_TOKEN` |
| Variable | `OCR_LLM_MODEL` |
| Variable | `OCR_LLM_USE_ANTHROPIC`（必须显式 `true` 或 `false`） |
| Variable | `OCR_ENABLED=true` |

禁止从其他项目复制或读取 Secret 值。停用时把 `OCR_ENABLED` 设为 `false`。

## GitHub Ruleset 建议

远端配置完成前不得宣称独立审查已强制执行。目标规则为：

- `main` 必须通过 PR，禁止直接推送、强推和删除；管理员不绕过。
- 必需检查使用实际 job 名称：`Classify PR changes`、`Analyze and Test`（含架构/隐私、Analyze、Unit/Widget）、`Android Integration`、`Android APK`、`iOS Integration`、`iOS Simulator`、`Documentation Consistency`。分类任务必需，防止分类失败时依赖任务全部跳过仍可合并。
- PR 必须同步最新 `main`，所有审查讨论解决后才能合并。
- OCR 当前默认关闭，不能设为 Required 或宣称独立语义审查已运行。只有取得单独的外发/费用授权并完成3～5个真实PR的命中、误报、漏报、耗时和费用记录后，才考虑将高等级发现升级为阻断。

## 有效性验证

每条确定性门禁必须至少有一个合法通过夹具和一个违规失败夹具。质量基线合并后，另建不合并的验证 PR：

1. `View → Repository/core/providers.dart` 应被架构门禁拒绝。
2. 未批准的有效手机号形状和数字 `loginUserName` Cookie 应被敏感数据门禁拒绝。
3. 删除 `flushResponseCookies` 后 SESSION-01 行为测试应失败。

门禁不能让上述已知错误变红时，不得以“检查已接入”宣称有效。
