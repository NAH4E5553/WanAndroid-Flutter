"""Classify pull request paths for deterministic and platform CI."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


ROOT_INFRASTRUCTURE_FILES = {
    "AGENTS.md",
    "AI项目开发技术指南.md",
    "Flutter版本实施方案.md",
}


def classify(paths: list[str]) -> tuple[bool, bool]:
    """Return (code_changed, platform_validation_required)."""
    normalized = [path.replace("\\", "/") for path in paths if path]
    code_changed = any(not path.lower().endswith(".md") for path in normalized)
    platform_required = any(
        not _is_development_infrastructure(path) for path in normalized
    )
    return code_changed, platform_required


def _is_development_infrastructure(path: str) -> bool:
    if path.lower().endswith(".md"):
        return True
    if path in ROOT_INFRASTRUCTURE_FILES:
        return True
    if path.startswith((".github/", "docs/", "test/tool/")):
        return True
    if path.startswith("tool/verify_") and path.endswith(".dart"):
        return True
    return path in {
        "tool/analyze_project.dart",
        "tool/standalone_package_config.json",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    changed = subprocess.check_output(
        ["git", "diff", "--name-only", "-z", args.base, args.head]
    ).split(b"\0")
    paths = [path.decode("utf-8") for path in changed if path]
    code_changed, platform_required = classify(paths)
    with args.output.open("a", encoding="utf-8") as output:
        output.write(f"code={str(code_changed).lower()}\n")
        output.write(f"platform={str(platform_required).lower()}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
