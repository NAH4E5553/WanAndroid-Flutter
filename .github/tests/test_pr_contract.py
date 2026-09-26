import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / ".github" / "scripts" / "verify_pr_contract.py"
SPEC = importlib.util.spec_from_file_location("verify_pr_contract", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


VALID_BODY = """
## 开工契约

- 任务类型：小修复
- 开工单：不适用（仅修复现有按钮文案）
- CONTRACT-ID：FIX-UI-TEXT
- Android 基线：固定提交中的 ProfileScreen
- 唯一事实源：现有 ProfileViewModel
- 规范身份/操作身份：不适用（不涉及业务身份）
- 生产调用链：ProfileScreen → ProfileViewModel

## 变更范围

- 关联契约 ID：UI-08
- 生产调用方：我的页面
- 明确非目标：不改变页面行为

## 实现偏差

偏差说明：无
"""


class PullRequestContractTest(unittest.TestCase):
    def test_documentation_change_does_not_require_contract(self):
        self.assertEqual([], MODULE.verify_body("", code_changed=False))

    def test_completed_code_contract_passes(self):
        self.assertEqual([], MODULE.verify_body(VALID_BODY, code_changed=True))

    def test_blank_fields_fail(self):
        body = VALID_BODY.replace("- 唯一事实源：现有 ProfileViewModel", "- 唯一事实源：")
        failures = MODULE.verify_body(body, code_changed=True)
        self.assertIn("PR field is missing or unchanged: 唯一事实源", failures)

    def test_untouched_template_choices_fail(self):
        body = VALID_BODY.replace(
            "- 任务类型：小修复",
            "- 任务类型：新功能 / 高风险功能 / 小修复 / 文档",
        )
        failures = MODULE.verify_body(body, code_changed=True)
        self.assertIn("PR field is missing or unchanged: 任务类型", failures)

    def test_not_applicable_with_reason_passes(self):
        body = VALID_BODY.replace(
            "- Android 基线：固定提交中的 ProfileScreen",
            "- Android 基线：不适用（仅调整仓库工具）",
        )
        self.assertEqual([], MODULE.verify_body(body, code_changed=True))

    def test_new_feature_requires_a_task_document(self):
        body = VALID_BODY.replace("- 任务类型：小修复", "- 任务类型：新功能")
        failures = MODULE.verify_body(body, code_changed=True)
        self.assertIn("新功能 must reference a committed task document", failures)

    def test_referenced_task_document_must_exist(self):
        body = VALID_BODY.replace(
            "- 开工单：不适用（仅修复现有按钮文案）",
            "- 开工单：`docs/tasks/FEATURE-DEMO.md`",
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            failures = MODULE.verify_task_reference(body, root=root)
            self.assertIn(
                "referenced task document does not exist: docs/tasks/FEATURE-DEMO.md",
                failures,
            )
            task = root / "docs" / "tasks" / "FEATURE-DEMO.md"
            task.parent.mkdir(parents=True)
            task.write_text("# Demo\n", encoding="utf-8")
            self.assertEqual([], MODULE.verify_task_reference(body, root=root))


if __name__ == "__main__":
    unittest.main()
