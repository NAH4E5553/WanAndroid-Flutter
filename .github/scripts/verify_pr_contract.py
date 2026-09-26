"""Require code pull requests to describe their implementation contract."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


REQUIRED_FIELDS = (
    "任务类型",
    "开工单",
    "CONTRACT-ID",
    "Android 基线",
    "唯一事实源",
    "规范身份/操作身份",
    "生产调用链",
    "关联契约 ID",
    "生产调用方",
    "明确非目标",
)
PLACEHOLDER_FRAGMENTS = (
    "docs/tasks/...",
    "新功能 / 高风险功能 / 小修复 / 文档",
    "不适用（说明理由）",
    "无 / 列出偏差、确认依据和验证影响",
    "待填写",
    "TODO",
    "TBD",
)


def verify_body(body: str, *, code_changed: bool) -> list[str]:
    """Return validation failures for the PR body."""
    if not code_changed:
        return []
    if not body.strip():
        return ["code PR must use .github/PULL_REQUEST_TEMPLATE.md"]

    failures: list[str] = []
    for label in REQUIRED_FIELDS:
        value = _field_value(body, label, bullet=True)
        if not _is_completed(value):
            failures.append(f"PR field is missing or unchanged: {label}")

    deviation = _field_value(body, "偏差说明", bullet=False)
    if not _is_completed(deviation):
        failures.append("PR field is missing or unchanged: 偏差说明")
    task_type = _field_value(body, "任务类型", bullet=True)
    task_document = _field_value(body, "开工单", bullet=True)
    if task_type in {"新功能", "高风险功能"} and (
        task_document is None or task_document.startswith("不适用")
    ):
        failures.append(f"{task_type} must reference a committed task document")
    return failures


def verify_task_reference(body: str, *, root: Path) -> list[str]:
    """Require a referenced task document to exist in the checkout."""
    value = _field_value(body, "开工单", bullet=True)
    if not _is_completed(value) or value is None or value.startswith("不适用"):
        return []
    relative = value.strip("`")
    if not relative.startswith("docs/tasks/") or not relative.endswith(".md"):
        return ["开工单 must be a plain docs/tasks/*.md path"]
    if not (root / relative).is_file():
        return [f"referenced task document does not exist: {relative}"]
    return []


def _field_value(body: str, label: str, *, bullet: bool) -> str | None:
    prefix = r"-[ \t]*" if bullet else ""
    match = re.search(
        rf"^{prefix}{re.escape(label)}[ \t]*[：:][ \t]*(.*?)[ \t]*$",
        body,
        flags=re.MULTILINE,
    )
    return None if match is None else match.group(1).strip()


def _is_completed(value: str | None) -> bool:
    if not value:
        return False
    upper = value.upper()
    return not any(fragment.upper() in upper for fragment in PLACEHOLDER_FRAGMENTS)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--event", type=Path, required=True)
    parser.add_argument("--code", choices=("true", "false"), required=True)
    args = parser.parse_args()

    event = json.loads(args.event.read_text(encoding="utf-8"))
    pull_request = event.get("pull_request") or {}
    body = pull_request.get("body") or ""
    failures = verify_body(body, code_changed=args.code == "true")
    if args.code == "true":
        failures.extend(verify_task_reference(body, root=Path.cwd()))
    if failures:
        for failure in failures:
            print(f"PR contract check failed: {failure}")
        return 1
    print("PR contract check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
