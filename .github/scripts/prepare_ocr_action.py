"""Build a log-safe adapter from hash-verified OCR 1.11.1 sources.

Upstream: Alibaba open-code-review, Apache-2.0; see .github/licenses/.
No model/GitHub credentials are read here. Do not fall back to the unsafe action.
"""
import argparse
import hashlib
from pathlib import Path
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
REVISION = "8d023aafcec05f8ba5628fca3eaba88078e5d201"
SOURCES = {
    "action.yml": "b52c1eb6d8335c5ec285118fba0a3bdd8dd646e5688fcbce5cf5c0e641ef7ad4",
    "scripts/github-actions/post-review-comments.js":
        "cfc257f4e6cb3013b6440c760bbd4182dfa76a3b5696718ce58672f83820deaf",
}
TARGET = ROOT / "build/ci-tools/ocr-action"
MAX_SOURCE_BYTES = 1024 * 1024


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError("unexpected upstream source layout")
    return source.replace(old, new, 1)


def step_span(source, name):
    marker = "    - name: " + name + "\n"
    if source.count(marker) != 1:
        raise ValueError("unexpected upstream step layout")
    start = source.index(marker)
    end = source.find("    - name: ", start + len(marker))
    return start, len(source) if end == -1 else end


def replace_step(source, name, replacement):
    start, end = step_span(source, name)
    return source[:start] + replacement + source[end:]


def adapt_action(source):
    # The caller already checks out the trusted PR base with full history and no
    # persisted credential. A second checkout would delete this generated action.
    source = replace_step(source, "Checkout base", "")
    source = replace_step(source, "Fetch PR head (fork-safe)", "")
    source = replace_step(source, "Compute merge-base", '''    - name: Compute merge-base
      env:
        OCR_BASE_SHA: ${{ github.event.pull_request.base.sha }}
      shell: bash
      run: |
        set -euo pipefail
        if ! MERGE_BASE=$(git merge-base "$OCR_BASE_SHA" "$HEAD_SHA" 2>/dev/null); then
          echo "::error::OCR_RANGE_FAILED: unable to resolve review range"
          exit 1
        fi
        echo "MERGE_BASE=$MERGE_BASE" >> "$GITHUB_ENV"

''')
    source = replace_once(source, "    default: latest\n", "    default: '1.11.1'\n")
    # No runtime switch may re-enable publication of raw result/error artifacts.
    source = replace_once(source, "    default: 'true'\n  sticky_summary:", "    default: 'false'\n  sticky_summary:")
    source = replace_step(source, "Upload review artifacts", "")

    # The composite action owns this exact-version installation for the whole
    # review. The CLI launcher otherwise starts a detached npm self-update on
    # every invocation, which can remove the global launcher/package tree
    # between the version, config, and review steps (upstream issue #703).
    for name in ("Install OpenCodeReview", "Configure OCR", "Run OpenCodeReview"):
        start, end = step_span(source, name)
        step = replace_once(
            source[start:end],
            "      env:\n",
            '''      env:
        # Keep the Action-owned runtime stable; do not self-update mid-review.
        OCR_NO_UPDATE: "1"
''',
        )
        source = source[:start] + step + source[end:]

    start, end = step_span(source, "Configure OCR")
    configure = source[start:end]
    configure = replace_once(configure, "      run: |\n", '''      run: |
        set +x
        # A config command can echo its value or return arbitrary error text.
        ocr() {
          if ! command ocr "$@" >/dev/null 2>&1; then
            echo "::error::OCR_CONFIG_FAILED: configuration failed; raw output suppressed"
            exit 1
          fi
        }
''')
    source = source[:start] + configure + source[end:]

    start, end = step_span(source, "Run OpenCodeReview")
    run = source[start:end]
    tail = run.index("        set +e\n")
    run = run[:tail] + '''        set +x
        umask 077
        OCR_RESULT_DIR=$(mktemp -d "$RUNNER_TEMP/ocr-review.XXXXXXXX")
        OCR_RESULT_PATH="$OCR_RESULT_DIR/result.json"
        cleanup_on_exit() {
          if [[ "${keep_result:-false}" != true ]]; then
            rm -f -- "$OCR_RESULT_PATH"
            rmdir -- "$OCR_RESULT_DIR"
          fi
        }
        trap cleanup_on_exit EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        echo "OCR_RESULT_DIR=$OCR_RESULT_DIR" >> "$GITHUB_ENV"
        echo "OCR_RESULT_PATH=$OCR_RESULT_PATH" >> "$GITHUB_ENV"
        set +e
        ocr review "${ARGS[@]}" > "$OCR_RESULT_PATH" 2>/dev/null
        OCR_EXIT_CODE=$?
        set -e
        echo "OCR_EXIT_CODE=$OCR_EXIT_CODE" >> "$GITHUB_ENV"
        echo "OCR review finished (exit code $OCR_EXIT_CODE); raw output suppressed."
        if [[ "$OCR_EXIT_CODE" == 0 ]]; then
          keep_result=true
        fi

'''
    source = source[:start] + run + source[end:]
    source = replace_once(
        source,
        'echo "ocr review exited with code ${OCR_EXIT_CODE}; see uploaded artifacts for details."',
        'echo "::error::OCR_REVIEW_FAILED: review failed (exit ${OCR_EXIT_CODE}); raw output suppressed"',
    )
    source = replace_once(source, "resultPath: '/tmp/ocr-result.json',", "resultPath: process.env.OCR_RESULT_PATH,")
    source = replace_once(source, "stderrPath: '/tmp/ocr-stderr.log',", "stderrPath: '/dev/null',")
    source = replace_once(source, "              log: (m) => core.info(m),", "              log: () => {},")
    # Pass this composite's path explicitly to nested github-script steps.
    old_roots = "const roots = [process.env.GITHUB_ACTION_PATH, process.env.GITHUB_WORKSPACE].filter(Boolean);"
    if source.count(old_roots) != 2:
        raise ValueError("unexpected helper lookup layout")
    source = source.replace(old_roots, "const roots = [process.env.OCR_ACTION_ROOT].filter(Boolean);")
    for name in ("Resolve review range", "Post review comments"):
        start, end = step_span(source, name)
        step = replace_once(source[start:end], "      env:\n", "      env:\n        OCR_ACTION_ROOT: ${{ github.action_path }}\n")
        source = source[:start] + step + source[end:]
    # These exceptions can contain remote response bodies. Keep only fixed labels.
    for old, new in (
        ("core.warning(`checkpoint: cannot read rule file ${rulePath} (${e.message}); forcing a full review.`);",
         "core.warning('OCR_RULE_UNREADABLE: forcing a full review.');"),
        ("core.warning(`checkpoint: cannot read .opencodereview/rule.json (${e.message}); forcing a full review.`);",
         "core.warning('OCR_LOCAL_RULE_UNREADABLE: forcing a full review.');"),
        ("core.warning(`checkpoint: could not resolve a range (${e.message}); reviewing the full range.`);",
         "core.warning('OCR_CHECKPOINT_UNAVAILABLE: reviewing the full range.');"),
    ):
        source = replace_once(source, old, new)

    start, end = step_span(source, "Post review comments")
    post = source[start:end]
    header, script = post.split("        script: |\n", 1)
    # The helper may reject with a GitHub response that contains comment bodies.
    post = header + "        script: |\n          try {\n" + "".join(
        "  " + line if line.strip() else line for line in script.splitlines(keepends=True)
    ) + '''          } catch {
            core.setFailed('OCR_COMMENT_POST_FAILED: invalid result or comment publication failed; raw details suppressed.');
          }

'''
    source = source[:start] + post + source[end:]
    source += '''    - name: Remove private review result
      if: always()
      shell: bash
      run: |
        set +x
        set -euo pipefail
        if [[ -z "${OCR_RESULT_DIR:-}" ]]; then
          exit 0
        fi
        # Delete only the one file/directory created by mktemp, never recursively.
        if [[ "$OCR_RESULT_DIR" != "$RUNNER_TEMP"/ocr-review.* ]] ||
           [[ "${OCR_RESULT_DIR%/*}" != "$RUNNER_TEMP" ]] ||
           [[ "${OCR_RESULT_PATH:-}" != "$OCR_RESULT_DIR/result.json" ]]; then
          echo "::error::OCR_CLEANUP_FAILED: unexpected result location"
          exit 1
        fi
        rm -f -- "$OCR_RESULT_PATH"
        if [[ -d "$OCR_RESULT_DIR" ]]; then
          rmdir -- "$OCR_RESULT_DIR"
        fi
'''
    return "# Generated log-safe adapter; source pinned and SHA-256 verified.\n" + source


def adapt_helper(source):
    start = source.index("  const log = (msg) => {")
    end = source.index("  const out = (name, value) => {", start)
    source = replace_once(source, source[start:end], "  const log = () => {}; // Suppress arbitrary API error bodies.\n")
    start = source.index("    log(`Failed to parse OCR output: ${e.message}`);")
    end = source.index("\n  const comments = result.comments || [];", start)
    source = replace_once(source, source[start:end], '''    // Never copy stderr or JSON parse errors into a PR comment or runner log.
    throw new Error("OCR_RESULT_INVALID");
  }
  if (!result || typeof result !== "object" || Array.isArray(result) ||
      (result.comments != null && !Array.isArray(result.comments)) ||
      !result.manifest || result.manifest.terminal_state !== "complete") {
    throw new Error("OCR_RESULT_INCOMPLETE");
  }
''')
    source = replace_once(
        source, "  const warnings = result.warnings || [];",
        '''  // Warnings may contain provider error responses. Preserve count, not text.
  const warnings = Array.isArray(result.warnings)
    ? result.warnings.map(() => "Review warning details suppressed for privacy.") : [];''',
    )
    source = replace_once(
        source, '    const message = result.message || "No comments generated. Looks good to me.";',
        '    const message = "Review completed with no findings. This does not replace CI or manual review.";',
    )
    source = replace_once(
        source, "    summaryBody += formatCommentMarkdown(comment, error);",
        '    summaryBody += formatCommentMarkdown(comment, "Comment publication failed; raw error details suppressed.");',
    )
    return source


def prepare(source_dir=None):
    verified = {}
    # Validate every byte of both inputs before creating executable output.
    for relative, checksum in SOURCES.items():
        if source_dir is not None:
            data = (source_dir / Path(relative).name).read_bytes()
        else:
            url = f"https://raw.githubusercontent.com/alibaba/open-code-review/{REVISION}/{relative}"
            with urllib.request.urlopen(url, timeout=30) as response:
                data = response.read(MAX_SOURCE_BYTES + 1)
        if len(data) > MAX_SOURCE_BYTES or hashlib.sha256(data).hexdigest() != checksum:
            raise ValueError("upstream integrity verification failed")
        verified[relative] = data.decode("utf-8")
    generated = {
        "action.yml": adapt_action(verified["action.yml"]),
        "scripts/github-actions/post-review-comments.js": adapt_helper(
            verified["scripts/github-actions/post-review-comments.js"]
        ),
    }
    for relative, content in generated.items():
        target = TARGET / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, help="Offline hash-verified reference files")
    args = parser.parse_args()
    try:
        prepare(args.source_dir)
    except Exception:
        print("::error::OCR_PREPARE_FAILED: source verification or adapter preparation failed; no fallback", file=sys.stderr)
        return 1
    print("OCR log-safe adapter prepared from verified sources.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
