"""Execute the generated adapter against fake processes/responses, never a model."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from test_ci_configuration import ROOT, UniqueKeyLoader
import yaml

ACTION_ROOT = ROOT / "build/ci-tools/ocr-action"
SENTINEL = "synthetic-private-fragment-NOT-A-REAL-CREDENTIAL"
spec = importlib.util.spec_from_file_location("ocr_adapter", ROOT / ".github/scripts/prepare_ocr_action.py")
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


class OcrLogSafety(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Prepared separately from pinned public sources, without credentials.
        cls.action = yaml.load((ACTION_ROOT / "action.yml").read_text(), Loader=UniqueKeyLoader)
        cls.steps = {s["name"]: s for s in cls.action["runs"]["steps"]}
        cls.node = shutil.which("node")
        if cls.node is None:
            raise RuntimeError("Node.js is required for OCR privacy regression tests")

    def setUp(self):
        scratch = ROOT / "build/ci-tests"
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.env = dict(os.environ)
        self.env.update(
            RUNNER_TEMP=str(self.directory), GITHUB_ENV=str(self.directory / "github-env"),
            HEAD_SHA="b" * 40, MERGE_BASE="a" * 40, RANGE_FROM="",
            REVIEW_TASK_TIMEOUT="15", OCR_REVIEW_CONCURRENCY="2", OCR_BACKGROUND="", OCR_RULE="",
            OCR_LLM_URL="https://example.invalid", OCR_LLM_MODEL="fixture", OCR_USE_ANTHROPIC="false",
            OCR_LLM_AUTH_HEADER="", OCR_EXTRA_BODY="{}", OCR_LANGUAGE="Chinese",
        )

    def shell(self, name, prefix="", env=None):
        return subprocess.run(
            ["bash", "--noprofile", "--norc", "-e", "-o", "pipefail", "-c",
             prefix + self.steps[name]["run"]],
            env=env or self.env, capture_output=True, text=True, timeout=15,
        )

    def result_env(self):
        return dict(line.split("=", 1) for line in Path(self.env["GITHUB_ENV"]).read_text().splitlines())

    def test_no_recheckout_upload_or_raw_error_in_generated_action(self):
        self.assertNotIn("Checkout base", self.steps)
        self.assertNotIn("Fetch PR head (fork-safe)", self.steps)
        self.assertNotIn("Upload review artifacts", self.steps)
        source = (ACTION_ROOT / "action.yml").read_text()
        for unsafe in ("cat /tmp/ocr", "ocr-stderr.log", "${e.message}", "default: latest", "git fetch"):
            self.assertNotIn(unsafe, source)
        self.assertEqual("always()", self.steps["Remove private review result"]["if"])
        self.assertEqual("1.11.1", self.action["inputs"]["ocr_version"]["default"])

    def test_every_action_owned_ocr_invocation_disables_self_update(self):
        invocation_pattern = re.compile(r"(?:^|[\s;&|(`/.$\"'])ocr\s+\S")
        for command in (
            "ocr review",
            "./bin/ocr review",
            "$OCR_BIN/ocr review",
            ".venv/bin/ocr review",
        ):
            self.assertRegex(command, invocation_pattern)

        invokers = []
        for name, step in self.steps.items():
            code = "\n".join(
                line for line in step.get("run", "").splitlines()
                if not re.match(r"^\s*#", line)
            )
            if invocation_pattern.search(code):
                invokers.append(name)

        self.assertEqual(
            {"Install OpenCodeReview", "Configure OCR", "Run OpenCodeReview"},
            set(invokers),
        )
        for name in invokers:
            self.assertEqual("1", self.steps[name].get("env", {}).get("OCR_NO_UPDATE"))

    def test_generated_bash_and_javascript_parse(self):
        for step in self.steps.values():
            if step.get("shell") == "bash":
                result = subprocess.run(["bash", "-n"], input=step["run"], text=True, capture_output=True)
                self.assertEqual(0, result.returncode, step["name"] + result.stderr)
            elif "script" in step.get("with", {}):
                script = re.sub(r"\$\{\{.*?\}\}", "false", step["with"]["script"])
                result = subprocess.run(
                    [self.node, "-e", "new (Object.getPrototypeOf(async function(){}).constructor)(process.argv[1])", script],
                    capture_output=True, text=True,
                )
                self.assertEqual(0, result.returncode, result.stderr)
        result = subprocess.run([self.node, "--check", str(ACTION_ROOT / "scripts/github-actions/post-review-comments.js")], capture_output=True)
        self.assertEqual(0, result.returncode, result.stderr)

    def test_success_keeps_private_result_until_cleanup_and_never_prints_it(self):
        prefix = 'ocr() { printf \'%s\' \'{"comments":[],"private":"' + SENTINEL + '"}\'; printf \'%s\' \' ' + SENTINEL + '\' >&2; };\n'
        result = self.shell("Run OpenCodeReview", prefix)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertNotIn(SENTINEL, result.stdout + result.stderr)
        values = self.result_env()
        path = Path(values["OCR_RESULT_PATH"])
        self.assertIn(SENTINEL, path.read_text())
        self.assertEqual(0o600, path.stat().st_mode & 0o777)
        self.assertEqual(0o700, path.parent.stat().st_mode & 0o777)
        self.assertEqual("0", values["OCR_EXIT_CODE"])
        cleanup = self.shell("Remove private review result", env={**self.env, **values})
        self.assertEqual(0, cleanup.returncode, cleanup.stderr)
        self.assertFalse(path.parent.exists())

    def test_failure_and_timeout_hide_stdout_stderr_and_remove_result(self):
        for code in (1, 124, 143):
            with self.subTest(code=code):
                prefix = "ocr() { printf '%s' '" + SENTINEL + "'; printf '%s' '" + SENTINEL + "' >&2; return " + str(code) + "; };\n"
                result = self.shell("Run OpenCodeReview", prefix)
                self.assertNotIn(SENTINEL, result.stdout + result.stderr)
                values = self.result_env()
                self.assertEqual(str(code), values["OCR_EXIT_CODE"])
                self.assertFalse(Path(values["OCR_RESULT_DIR"]).exists())
                failure = self.shell("Fail job on OCR error", env={**self.env, **values})
                self.assertEqual(code, failure.returncode)
                self.assertIn("OCR_REVIEW_FAILED", failure.stdout)

    def test_cancellation_cleans_private_file(self):
        result = self.shell("Run OpenCodeReview", "ocr() { kill -TERM $$; return 143; };\n")
        self.assertEqual(143, result.returncode)
        self.assertEqual([], list(self.directory.glob("ocr-review.*")))

    def test_cleanup_refuses_paths_it_did_not_create(self):
        protected = self.directory / "not-an-ocr-result"
        protected.mkdir()
        file = protected / "result.json"
        file.write_text("keep")
        result = self.shell("Remove private review result", env={
            **self.env, "OCR_RESULT_DIR": str(protected), "OCR_RESULT_PATH": str(file),
        })
        self.assertNotEqual(0, result.returncode)
        self.assertEqual("keep", file.read_text())

    def test_config_failure_is_hidden_and_stops_at_first_failed_command(self):
        binary = self.directory / "ocr"
        binary.write_text("#!/bin/sh\nprintf '%s' '" + SENTINEL + "'\nprintf '%s' '" + SENTINEL + "' >&2\nexit 1\n")
        binary.chmod(0o700)
        result = self.shell("Configure OCR", env={**self.env, "PATH": str(self.directory) + os.pathsep + self.env["PATH"]})
        self.assertEqual(1, result.returncode)
        self.assertNotIn(SENTINEL, result.stdout + result.stderr)
        self.assertEqual(1, result.stdout.count("OCR_CONFIG_FAILED"))

    def test_missing_git_objects_fail_closed(self):
        result = self.shell("Compute merge-base", env={**self.env, "OCR_BASE_SHA": "c" * 40})
        self.assertNotEqual(0, result.returncode)
        self.assertIn("OCR_RANGE_FAILED", result.stdout)

    def test_source_integrity_and_layout_fail_closed(self):
        (self.directory / "action.yml").write_text("tampered")
        with patch.object(adapter, "TARGET", self.directory / "output"):
            with self.assertRaises(ValueError):
                adapter.prepare(self.directory)
        self.assertFalse((self.directory / "output").exists())
        with self.assertRaises(ValueError):
            adapter.replace_once("different", "expected", "replacement")
        with self.assertRaises(ValueError):
            adapter.replace_once("expected expected", "expected", "replacement")

    def test_fake_github_publication_and_checkpoint_contracts(self):
        post_script = self.steps["Post review comments"]["with"]["script"]
        post_script = re.sub(r"\$\{\{.*?\}\}", "true", post_script)
        result = subprocess.run(
            [self.node, str(ROOT / ".github/tests/ocr_post_privacy.cjs")],
            input=json.dumps({"script": post_script, "actionRoot": str(ACTION_ROOT), "sentinel": SENTINEL}),
            text=True, capture_output=True, timeout=30,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("OCR posting privacy fixtures passed", result.stdout)
        self.assertNotIn(SENTINEL, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
