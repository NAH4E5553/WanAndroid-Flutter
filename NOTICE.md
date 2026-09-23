# 第三方来源说明

OpenCodeReview 日志安全适配基于 Alibaba `open-code-review`，固定来源提交为
`8d023aafcec05f8ba5628fca3eaba88078e5d201`，Copyright 2026
alibaba/open-code-review Contributors。

准备脚本对上游 `action.yml` 和评论辅助脚本执行固定 SHA-256 校验，再生成
本项目使用的日志安全版本；适配内容包括禁止运行期自升级、抑制原始模型响应与
stderr、限制临时结果权限和位置、失败关闭及清理。适配器和规则只从 PR 基线
加载，不执行 PR head 中的准备脚本。

上游项目使用 Apache License 2.0，完整许可见
`.github/licenses/open-code-review-LICENSE`。本仓库不包含模型凭据；启用 OCR 前
必须单独确认 Flutter 代码上下文外发和费用边界，并为本仓库配置独立 Secret。
