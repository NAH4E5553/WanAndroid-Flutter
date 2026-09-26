from pathlib import Path
import importlib.util
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / ".github/scripts/classify_pr_changes.py"
SPEC = importlib.util.spec_from_file_location("classify_pr_changes", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ChangeClassificationTest(unittest.TestCase):
    def test_markdown_only_skips_code_and_platform_validation(self):
        self.assertEqual((False, False), MODULE.classify(["docs/说明.md"]))

    def test_development_infrastructure_skips_platform_validation(self):
        paths = [
            ".github/workflows/stage2.yml",
            ".github/scripts/verify_pr_contract.py",
            "AGENTS.md",
            "docs/开发任务模板.md",
            "tool/verify_pr.dart",
            "tool/verify_stage1.dart",
        ]
        self.assertEqual((True, False), MODULE.classify(paths))

    def test_flutter_product_code_requires_platform_validation(self):
        self.assertEqual(
            (True, True),
            MODULE.classify(["lib/src/features/home/view/home_screen.dart"]),
        )

    def test_platform_and_build_inputs_require_platform_validation(self):
        for path in (
            "android/app/build.gradle.kts",
            "ios/Runner/Info.plist",
            "pubspec.yaml",
            "tool/generate_launcher_icons.dart",
        ):
            with self.subTest(path=path):
                self.assertEqual((True, True), MODULE.classify([path]))


if __name__ == "__main__":
    unittest.main()
