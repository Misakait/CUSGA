"""卡牌表格同步工具的纯 Python 回归测试。"""

from __future__ import annotations

import importlib.util
import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("export_current_cards.py")


def load_sync_module():
    """以独立模块名加载同步脚本，避免测试触发命令行入口。"""
    spec = importlib.util.spec_from_file_location("card_table_sync_test", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("无法加载卡牌表格同步脚本。")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class CardTableSyncSafetyTests(unittest.TestCase):
    """覆盖路径约束、原子写入和根资源字段替换的安全边界。"""

    @classmethod
    def setUpClass(cls) -> None:
        """加载被测模块一次，避免每个用例重复解析大型同步脚本。"""
        cls.sync_module = load_sync_module()

    def test_managed_resource_path_rejects_directory_escape(self) -> None:
        """表格路径不能借由 `..` 越出受管资源目录。"""
        with tempfile.TemporaryDirectory() as temporary_directory:
            original_root = self.sync_module.ROOT
            self.sync_module.ROOT = Path(temporary_directory)
            try:
                errors: list[str] = []
                managed_directory = self.sync_module.ROOT / "resources" / "skill_cards"
                result = self.sync_module.validate_managed_resource_path(
                    "res://resources/skill_cards/../../outside.tres",
                    managed_directory,
                    "resource_path",
                    errors,
                )
            finally:
                self.sync_module.ROOT = original_root
        self.assertIsNone(result)
        self.assertEqual(len(errors), 1)
        self.assertIn("路径穿越", errors[0])

    def test_atomic_text_write_keeps_complete_new_content(self) -> None:
        """原子写入完成后目标文件只会包含完整的新内容。"""
        with tempfile.TemporaryDirectory() as temporary_directory:
            original_root = self.sync_module.ROOT
            self.sync_module.ROOT = Path(temporary_directory)
            try:
                target_path = self.sync_module.ROOT / "resources" / "example.tres"
                target_path.parent.mkdir(parents=True)
                target_path.write_text("旧内容", encoding="utf-8")
                self.sync_module.write_text_atomically(target_path, "新内容")
                result = target_path.read_text(encoding="utf-8")
            finally:
                self.sync_module.ROOT = original_root
        self.assertEqual(result, "新内容")

    def test_root_resource_update_does_not_touch_subresource(self) -> None:
        """同名字段存在于子资源时，只允许更新 `[resource]` 段中的字段。"""
        text = """[sub_resource type=\"Resource\" id=\"Child\"]
CardName = \"子资源名称\"

[resource]
CardName = \"根资源名称\"
"""
        updated = self.sync_module.replace_or_add_resource_property(
            text, "CardName", '"更新后的根资源名称"'
        )
        self.assertIn('CardName = "子资源名称"', updated)
        self.assertIn('CardName = "更新后的根资源名称"', updated)

    def test_resource_batch_restores_already_written_files_after_failure(self) -> None:
        """批量导入中途失败时，已经提交的资源必须从自动备份恢复。"""
        with tempfile.TemporaryDirectory() as temporary_directory:
            original_root = self.sync_module.ROOT
            original_backup_directory = self.sync_module.BACKUP_DIR
            self.sync_module.ROOT = Path(temporary_directory)
            self.sync_module.BACKUP_DIR = self.sync_module.ROOT / "card_table" / ".sync_backups"
            first_path = self.sync_module.ROOT / "resources" / "first.tres"
            second_path = self.sync_module.ROOT / "resources" / "second.tres"
            first_path.parent.mkdir(parents=True)
            first_path.write_text("第一份旧内容", encoding="utf-8")
            second_path.write_text("第二份旧内容", encoding="utf-8")
            original_writer = self.sync_module.write_text_atomically

            def fail_second_write(path: Path, content: str, encoding: str = "utf-8") -> None:
                """模拟第二个资源的磁盘写入失败。"""
                if path == second_path and content == "第二份新内容":
                    raise self.sync_module.CardTableSyncError("模拟写入失败")
                original_writer(path, content, encoding)

            self.sync_module.write_text_atomically = fail_second_write
            try:
                with self.assertRaises(self.sync_module.CardTableSyncError):
                    self.sync_module.write_resource_batch_atomically(
                        {first_path: "第一份新内容", second_path: "第二份新内容"}
                    )
            finally:
                self.sync_module.write_text_atomically = original_writer
                self.sync_module.ROOT = original_root
                self.sync_module.BACKUP_DIR = original_backup_directory
            self.assertEqual(first_path.read_text(encoding="utf-8"), "第一份旧内容")
            self.assertEqual(second_path.read_text(encoding="utf-8"), "第二份旧内容")

    def test_header_validation_reports_missing_column(self) -> None:
        """删除必要列必须在预检阶段被拦截，而不是以空值导入资源。"""
        errors: list[str] = []
        self.sync_module.validate_table_headers(
            ["resource_path", "card_name"],
            self.sync_module.SKILL_HEADERS,
            "技能表",
            errors,
        )
        self.assertEqual(len(errors), 1)
        self.assertIn("缺少列", errors[0])

    def test_import_failure_returns_nonzero_result_without_creating_resources(self) -> None:
        """缺少表格时 CLI 必须返回失败摘要，且不能创建任何资源目录。"""
        with tempfile.TemporaryDirectory() as temporary_directory:
            root_path = Path(temporary_directory)
            table_directory = root_path / "card_table"
            table_directory.mkdir()
            copied_script = table_directory / "export_current_cards.py"
            # 失败结果文件位于临时项目内，确保原子写入错误信息可使用项目相对路径。
            result_file = table_directory / ".card_csv_sync_result.json"
            # 固定请求标识便于断言失败结果没有串用其他调用状态。
            request_id = "failure-request"
            shutil.copy2(SCRIPT_PATH, copied_script)
            completed = subprocess.run(
                [
                    sys.executable,
                    str(copied_script),
                    "--import",
                    "--result-file",
                    str(result_file),
                    "--request-id",
                    request_id,
                ],
                cwd=root_path,
                check=False,
                capture_output=True,
                text=True,
                encoding="utf-8",
            )
            # 显式以 UTF-8 读取结果文件，验证中文错误通道不依赖系统代码页。
            result_payload = json.loads(result_file.read_text(encoding="utf-8"))
            resources_directory_exists = (root_path / "resources").exists()
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("CARD_CSV_SYNC_RESULT=", completed.stdout)
        self.assertIn('"success": false', completed.stdout)
        self.assertFalse(result_payload["success"])
        self.assertEqual(result_payload["request_id"], request_id)
        self.assertFalse(resources_directory_exists)

    def test_result_file_is_utf8_and_contains_current_request(self) -> None:
        """成功结果必须以 UTF-8 写入文件，并携带当前请求标识与准确动作。"""
        with tempfile.TemporaryDirectory() as temporary_directory:
            # 临时替换项目根目录，使结果文件写入完全隔离于真实工程。
            original_root = self.sync_module.ROOT
            self.sync_module.ROOT = Path(temporary_directory)
            # 结果文件沿用插件约定的隐藏文件名，但只存在于临时目录。
            result_file = self.sync_module.ROOT / "card_table" / ".card_csv_sync_result.json"
            # 捕获控制台摘要，验证结果文件与兼容输出使用同一份中文载荷。
            captured_output = io.StringIO()
            try:
                with redirect_stdout(captured_output):
                    write_succeeded = self.sync_module.print_result(
                        self.sync_module.SyncResult("卡牌同步成功"),
                        True,
                        "",
                        result_file,
                        "success-request",
                    )
                # 读取原始字节后显式 UTF-8 解码，验证结果文件编码契约。
                raw_result = result_file.read_bytes()
                result_payload = json.loads(raw_result.decode("utf-8"))
            finally:
                self.sync_module.ROOT = original_root
        self.assertTrue(write_succeeded)
        self.assertEqual(result_payload["action"], "卡牌同步成功")
        self.assertEqual(result_payload["request_id"], "success-request")
        self.assertIn("卡牌同步成功", captured_output.getvalue())


if __name__ == "__main__":
    unittest.main()
