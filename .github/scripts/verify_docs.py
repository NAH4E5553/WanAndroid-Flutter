"""Check project Markdown links, required status references and phone literals."""

from pathlib import Path
import re
import sys
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[2]
REQUIRED = (
    ROOT / "AGENTS.md",
    ROOT / "AI项目开发技术指南.md",
    ROOT / "Flutter版本实施方案.md",
    ROOT / "docs/阶段状态与决策记录.md",
    ROOT / "docs/阶段0行为对照矩阵.md",
)
SYNTHETIC_PHONES = {"13800138000", "13900139000"}
PHONE = re.compile(r"(?<![0-9])1[3-9][0-9]{9}(?![0-9])")
INLINE_LINK = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
REFERENCE_LINK = re.compile(r"^\s*\[[^\]]+\]:\s*(\S+)", re.MULTILINE)


def markdown_files():
    for path in sorted(ROOT.rglob("*.md")):
        relative = path.relative_to(ROOT).as_posix()
        if relative.startswith(("build/", ".dart_tool/", "third_party/")):
            continue
        yield path


def local_target(source, raw):
    value = raw.strip().strip("<>").split()[0]
    if not value or value.startswith(("#", "http://", "https://", "mailto:")):
        return None
    value = unquote(value.split("#", 1)[0].split("?", 1)[0])
    if not value or value.startswith("/"):
        return None
    return (source.parent / value).resolve()


def main():
    failures = []
    for required in REQUIRED:
        if not required.is_file():
            failures.append(f"missing required document: {required.relative_to(ROOT)}")

    status_reference = "docs/阶段状态与决策记录.md"
    for path in (ROOT / "AGENTS.md", ROOT / "AI项目开发技术指南.md", ROOT / "Flutter版本实施方案.md"):
        if path.is_file() and status_reference not in path.read_text(encoding="utf-8"):
            failures.append(f"{path.relative_to(ROOT)} does not name the status authority")

    checked_links = 0
    for path in markdown_files():
        source = path.read_text(encoding="utf-8")
        for match in (*INLINE_LINK.findall(source), *REFERENCE_LINK.findall(source)):
            target = local_target(path, match)
            if target is None:
                continue
            checked_links += 1
            if not target.exists():
                failures.append(
                    f"broken local link: {path.relative_to(ROOT)} -> {match}"
                )
        for line_number, line in enumerate(source.splitlines(), start=1):
            for match in PHONE.finditer(line):
                if match.group(0) not in SYNTHETIC_PHONES:
                    failures.append(
                        f"unapproved phone literal: {path.relative_to(ROOT)}:{line_number}"
                    )

    if failures:
        print("Documentation check failed:", file=sys.stderr)
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    print(f"Documentation check passed ({checked_links} local links).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
