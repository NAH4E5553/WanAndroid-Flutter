from pathlib import Path
import json
import re
import subprocess
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]


class UniqueKeyLoader(yaml.SafeLoader):
    pass


def _construct_mapping(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise ValueError(f"duplicate YAML key: {key}")
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    _construct_mapping,
)


class CiConfigurationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ocr_path = ROOT / ".github/workflows/open-code-review.yml"
        cls.ocr_source = cls.ocr_path.read_text(encoding="utf-8")
        cls.ocr = yaml.load(cls.ocr_source, Loader=UniqueKeyLoader)
        cls.stage_source = (ROOT / ".github/workflows/stage2.yml").read_text(
            encoding="utf-8"
        )
        cls.stage = yaml.load(cls.stage_source, Loader=UniqueKeyLoader)
        cls.documentation = yaml.load(
            (ROOT / ".github/workflows/documentation.yml").read_text(
                encoding="utf-8"
            ),
            Loader=UniqueKeyLoader,
        )
        cls.ruleset = json.loads(
            (ROOT / ".github/ruleset-main.json").read_text(encoding="utf-8")
        )

    def test_ocr_uses_pull_request_without_target_execution(self):
        self.assertIn("pull_request", self.ocr["on"])
        self.assertNotIn("pull_request_target", self.ocr_source)
        self.assertIn("github.event.pull_request.base.sha", self.ocr_source)
        self.assertIn("persist-credentials: false", self.ocr_source)
        self.assertIn("fetch-depth: 0", self.ocr_source)

    def test_ocr_is_disabled_without_explicit_variable(self):
        condition = self.ocr["jobs"]["review"]["if"]
        self.assertIn("vars.OCR_ENABLED == 'true'", condition)
        self.assertIn("draft == false", condition)
        self.assertIn("head.repo.full_name == github.repository", condition)

    def test_ocr_permissions_and_triggers_are_minimal(self):
        self.assertEqual({"contents": "read"}, self.ocr["permissions"])
        permissions = self.ocr["jobs"]["review"]["permissions"]
        self.assertEqual("read", permissions["contents"])
        self.assertEqual("write", permissions["pull-requests"])
        paths = self.ocr["on"]["pull_request"]["paths"]
        for required in ("**/*.dart", "pubspec.yaml", ".github/**"):
            self.assertIn(required, paths)

    def test_review_executes_only_generated_base_adapter(self):
        steps = self.ocr["jobs"]["review"]["steps"]
        checkout = next(step for step in steps if step.get("name") == "Checkout trusted base")
        self.assertEqual(
            "${{ github.event.pull_request.base.sha }}",
            checkout["with"]["ref"],
        )
        review = next(step for step in steps if step.get("name") == "Review pull request")
        self.assertEqual("./build/ci-tools/ocr-action", review["uses"])
        self.assertEqual("1.11.1", review["with"]["ocr_version"])
        self.assertEqual("false", review["with"]["upload_artifacts"])

    def test_deterministic_gates_run_in_primary_ci(self):
        for command in (
            "tool/verify_architecture.dart",
            "tool/verify_architecture_fixtures.dart",
            "tool/verify_sensitive_data.dart",
            "tool/verify_sensitive_data_fixtures.dart",
        ):
            self.assertIn(command, self.stage_source)

    def test_stage_five_runs_both_platform_integration_suites(self):
        self.assertIn("android-integration:", self.stage_source)
        self.assertIn("ios-integration:", self.stage_source)
        self.assertEqual(
            2,
            self.stage_source.count(
                "flutter test integration_test/stage5_ci_test.dart"
            ),
        )

    def test_required_checks_exist_for_every_pull_request(self):
        self.assertIn("pull_request", self.stage["on"])
        self.assertNotIn("paths", self.stage["on"]["pull_request"] or {})
        self.assertNotIn("paths-ignore", self.stage["on"]["pull_request"] or {})
        self.assertIn("pull_request", self.documentation["on"])
        self.assertNotIn("paths", self.documentation["on"]["pull_request"] or {})
        self.assertNotIn("paths-ignore", self.documentation["on"]["pull_request"] or {})
        jobs = self.stage["jobs"]
        self.assertEqual("Classify PR changes", jobs["classify-changes"]["name"])
        self.assertEqual("classify-changes", jobs["analyze-and-test"]["needs"])
        for job_id in (
            "analyze-and-test",
            "android-integration",
            "android-shell",
            "ios-integration",
            "ios-shell",
        ):
            self.assertEqual("classify-changes", jobs[job_id]["needs"])
            self.assertEqual(
                "needs.classify-changes.outputs.code == 'true'", jobs[job_id]["if"]
            )
        self.assertEqual(
            "Documentation Consistency",
            self.documentation["jobs"]["documentation"]["name"],
        )

    def test_ruleset_requires_exact_ci_jobs_from_github_actions(self):
        rules = {rule["type"]: rule for rule in self.ruleset["rules"]}
        self.assertEqual("active", self.ruleset["enforcement"])
        self.assertEqual([], self.ruleset["bypass_actors"])
        self.assertEqual(
            ["refs/heads/main"],
            self.ruleset["conditions"]["ref_name"]["include"],
        )
        self.assertIn("pull_request", rules)
        self.assertIn("deletion", rules)
        self.assertIn("non_fast_forward", rules)
        self.assertEqual(
            0, rules["pull_request"]["parameters"]["required_approving_review_count"]
        )
        checks = rules["required_status_checks"]["parameters"]
        self.assertTrue(checks["strict_required_status_checks_policy"])
        actual = {check["context"] for check in checks["required_status_checks"]}
        expected = {job["name"] for job in self.stage["jobs"].values()}
        expected.add(self.documentation["jobs"]["documentation"]["name"])
        self.assertEqual(expected, actual)
        self.assertEqual(
            {15368},
            {check["integration_id"] for check in checks["required_status_checks"]},
        )

    def test_all_workflow_yaml_and_bash_steps_parse(self):
        for path in sorted((ROOT / ".github/workflows").glob("*.yml")):
            workflow = yaml.load(path.read_text(encoding="utf-8"), Loader=UniqueKeyLoader)
            self.assertIn("on", workflow, path)
            for job in workflow.get("jobs", {}).values():
                for step in job.get("steps", []):
                    command = step.get("run")
                    if not command:
                        continue
                    shell = step.get("shell", "bash")
                    if not shell.startswith("bash"):
                        continue
                    sanitized = re.sub(r"\$\{\{.*?\}\}", "fixture", command)
                    result = subprocess.run(
                        ["bash", "-n"],
                        input=sanitized,
                        text=True,
                        capture_output=True,
                    )
                    self.assertEqual(
                        0,
                        result.returncode,
                        f"{path.name}: {step.get('name', command)}: {result.stderr}",
                    )


if __name__ == "__main__":
    unittest.main()
