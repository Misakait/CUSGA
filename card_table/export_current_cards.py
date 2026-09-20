#!/usr/bin/env python3
# pyright: reportUnknownVariableType=false, reportUnknownArgumentType=false, reportUnknownMemberType=false, reportUnusedCallResult=false, reportUnusedVariable=false, reportAny=false
"""技能卡与怪物卡 CSV 双向同步工具。

该脚本由 Godot 编辑器插件调用，也可以在命令行独立执行：
- 默认或 `--export`：从 `.tres` 资源导出 CSV。
- `--import`：把 CSV 中的基础字段、技能归属和新增资源回写到 `.tres`。
- `--sync`：先导入 CSV，再重新导出，保证表格和资源双向一致。
"""

from __future__ import annotations

import argparse
import ast
import csv
import datetime
import html
import json
import math
import os
import re
import shutil
import sys
import tempfile
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import cast, Iterable
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
SKILL_CARD_DIR = ROOT / "resources" / "skill_cards"
COMBAT_SKILL_DIR = ROOT / "resources" / "combat_skills"
MONSTER_DIR = ROOT / "resources" / "monster"
OUT_DIR = ROOT / "card_table"
SKILL_CSV = OUT_DIR / "skill_cards.csv"
MONSTER_CSV = OUT_DIR / "monster_cards.csv"
XLSX_FILE = OUT_DIR / "card_tables.xlsx"
PENDING_XLSX_FILE = OUT_DIR / "card_tables.pending.xlsx"
STATE_FILE = OUT_DIR / ".sync_state.json"
BACKUP_DIR = OUT_DIR / ".sync_backups"
BACKUP_RETENTION_COUNT = 10
RESULT_PREFIX = "CARD_CSV_SYNC_RESULT="


def configure_console_encoding() -> None:
    """强制脚本结果使用 UTF-8，避免 Windows 管道输出损坏插件要解析的中文 JSON。"""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            # 某些嵌入式解释器没有可重配的标准流，保留其默认行为而不阻断同步。
            continue


configure_console_encoding()

SKILL_CARD_SCRIPT = "res://resources/item/card/skill_card_data.gd"
SKILL_CARD_SCRIPT_UID = "uid://d1ln6w8iaa4px"
COMBAT_SKILL_SCRIPT = "res://core/combat/skills/combat_skill_data.gd"
MONSTER_SCRIPT = "res://resources/monster/monster_data.gd"
STARTING_STATS_SCRIPT = "res://resources/stats/starting_stats.gd"
MONSTER_SKILL_ENTRY_SCRIPT = "res://resources/monster/monster_skill_entry_data.gd"
MONSTER_SKILL_SET_SCRIPT = "res://resources/monster/monster_skill_set_data.gd"

SKILL_HEADERS = [
    "resource_path",
    "id_slug",
    "card_id",
    "card_name",
    "description",
    "icon_path",
    "cost",
    "tags",
    "combat_skill_path",
    "element",
    "targeting_type",
    "monster_owners",
]

BASE_STAT_FIELDS = [
    ("base_phys_atk", "BasePhysAtk", "100.0"),
    ("base_phys_def", "BasePhysDef", "100.0"),
    ("base_mag_power", "BaseMagPower", "100.0"),
    ("base_mag_resist", "BaseMagResist", "100.0"),
    ("base_speed", "BaseSpeed", "100.0"),
    ("base_max_health", "BaseMaxHealth", "1000.0"),
    ("base_fixed_phys_penetration", "BaseFixedPhysPenetration", "0.0"),
    ("base_phys_penetration_rate", "BasePhysPenetrationRate", "0.0"),
    ("base_fixed_magic_penetration", "BaseFixedMagicPenetration", "0.0"),
    ("base_magic_penetration_rate", "BaseMagicPenetrationRate", "0.0"),
    ("base_crit_rate", "BaseCritRate", "0.0"),
    ("base_crit_damage", "BaseCritDamage", "1.5"),
    ("base_evasion_rate", "BaseEvasionRate", "0.0"),
    ("base_lifesteal_rate", "BaseLifestealRate", "0.0"),
]

MONSTER_HEADERS = [
    "resource_path",
    "id_slug",
    "monster_name",
    "element",
    "faction",
    "model_scene_path",
    "behavior_tree_scene_path",
    "skill_names",
    *[csv_key for csv_key, _gd_key, _default_value in BASE_STAT_FIELDS],
]


ELEMENT_VALUE_TO_LABEL = {
    "0": "无",
    "1": "木",
    "2": "金",
    "3": "水",
    "4": "土",
    "5": "火",
}
ELEMENT_LABEL_TO_VALUE = {
    label: value for value, label in ELEMENT_VALUE_TO_LABEL.items()
}
ELEMENT_LABEL_OPTIONS = ["无", "金", "木", "水", "火", "土"]

TARGETING_VALUE_TO_LABEL = {
    "0": "自身",
    "1": "单体敌人",
    "2": "全体敌人",
    "3": "任意单体单位",
    "4": "全体单位",
    "5": "随机敌人",
    "6": "扩散敌人",
}
TARGETING_LABEL_TO_VALUE = {
    label: value for value, label in TARGETING_VALUE_TO_LABEL.items()
}
TARGETING_LABEL_OPTIONS = [
    "自身",
    "单体敌人",
    "全体敌人",
    "任意单体单位",
    "全体单位",
    "随机敌人",
    "扩散敌人",
]

STAT_FIELDS = [
    ("base_phys_atk", "BasePhysAtk", "100.0"),
    ("phys_atk_growth", "PhysAtkGrowth", "25.0"),
    ("base_phys_def", "BasePhysDef", "100.0"),
    ("phys_def_growth", "PhysDefGrowth", "20.0"),
    ("base_mag_power", "BaseMagPower", "100.0"),
    ("mag_power_growth", "MagPowerGrowth", "30.0"),
    ("base_mag_resist", "BaseMagResist", "100.0"),
    ("mag_resist_growth", "MagResistGrowth", "20.0"),
    ("base_speed", "BaseSpeed", "100.0"),
    ("speed_growth", "SpeedGrowth", "5.0"),
    ("base_max_health", "BaseMaxHealth", "1000.0"),
    ("max_health_growth", "MaxHealthGrowth", "0.0"),
    ("base_fixed_phys_penetration", "BaseFixedPhysPenetration", "0.0"),
    ("fixed_phys_penetration_growth", "FixedPhysPenetrationGrowth", "0.0"),
    ("base_phys_penetration_rate", "BasePhysPenetrationRate", "0.0"),
    ("phys_penetration_rate_growth", "PhysPenetrationRateGrowth", "0.0"),
    ("base_fixed_magic_penetration", "BaseFixedMagicPenetration", "0.0"),
    ("fixed_magic_penetration_growth", "FixedMagicPenetrationGrowth", "0.0"),
    ("base_magic_penetration_rate", "BaseMagicPenetrationRate", "0.0"),
    ("magic_penetration_rate_growth", "MagicPenetrationRateGrowth", "0.0"),
    ("base_crit_rate", "BaseCritRate", "0.0"),
    ("crit_rate_growth", "CritRateGrowth", "0.0"),
    ("base_crit_damage", "BaseCritDamage", "1.5"),
    ("crit_damage_growth", "CritDamageGrowth", "0.0"),
    ("base_evasion_rate", "BaseEvasionRate", "0.0"),
    ("evasion_rate_growth", "EvasionRateGrowth", "0.0"),
    ("base_lifesteal_rate", "BaseLifestealRate", "0.0"),
    ("lifesteal_rate_growth", "LifestealRateGrowth", "0.0"),
]

# 表格里的百分比字段沿用"省略百分号"的书写习惯：5 表示 5%，13 表示 13%。
# 运行时（AttributeComponent 会把百分比钳制到 0~1，AttributeSummaryUI 显示时再乘以 100）
# 统一使用 0~1 小数，因此两个方向必须在这里换算，否则表格里的 5 会被钳制成 100%。
# 注意：暴击伤害是"倍率"而不是百分比（2.0 表示 200% 伤害），不参与该换算。
PERCENT_STAT_KEYS = frozenset(
    {
        "base_phys_penetration_rate",
        "base_magic_penetration_rate",
        "base_crit_rate",
        "base_evasion_rate",
        "base_lifesteal_rate",
        "phys_penetration_rate_growth",
        "magic_penetration_rate_growth",
        "crit_rate_growth",
        "evasion_rate_growth",
        "lifesteal_rate_growth",
    }
)

# 百分比字段在表格中的换算比例与合理范围（百分号写法下不应超过 100）。
PERCENT_SCALE = 100.0


class CardTableSyncError(Exception):
    """表示可预期的同步失败，并由命令行入口转换为清晰的错误结果。"""


class CardTableValidationError(CardTableSyncError):
    """表示表格预检失败；抛出后不得进入任何资源写入流程。"""


@dataclass
class SyncResult:
    """记录一次同步操作的最终状态，供 Godot 插件与命令行统一消费。"""

    action: str
    changed_files: list[Path] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def to_payload(
        self, success: bool, error: str = "", request_id: str = ""
    ) -> dict[str, object]:
        """转换为编辑器可解析的稳定 JSON 结果。

        参数:
            success: 整次操作是否完整成功。
            error: 失败时展示给用户的错误原因。
            request_id: Godot 为本次调用生成的唯一标识，用于拒绝旧结果文件。
        返回:
            可同时写入 UTF-8 结果文件与控制台的 JSON 字典。
        """
        return {
            "success": success,
            "action": self.action,
            "changed_files": [to_res_path(path) for path in self.changed_files],
            "warnings": self.warnings,
            "error": error,
            "request_id": request_id,
        }


def _format_stat_number(value: float) -> str:
    """把属性数值格式化为稳定的表格/资源字面量，避免浮点误差污染同步结果。

    参数:
        value: 待格式化的数值。
    返回:
        至少保留一位小数的十进制字符串，例如 ``5.0``、``0.05``、``13.0``。
    """
    rounded = round(value, 6)
    text = f"{rounded:.6f}".rstrip("0")
    return text if not text.endswith(".") else text + "0"


def _parse_stat_number(text: str) -> float | None:
    """解析表格或资源中的数值文本。

    参数:
        text: 单元格或字段文本，可能为空、带空白或包含非法内容。
    返回:
        解析成功时返回浮点数；文本为空或非法时返回 None，交由调用方保持原值。
    """
    try:
        return float((text or "").strip())
    except ValueError:
        return None


def _warn_if_percent_out_of_range(csv_key: str, percent_value: float) -> None:
    """对明显不合理的百分比表格值打印可见警告。

    曾经表格里写成 5 的闪避率被原样写入资源，运行时又被静默钳制到 1.0，导致"必定命中/必定闪避"
    这类无法从战斗表现反推的数据问题。这里主动把越界值暴露出来，替代无声的钳制。

    参数:
        csv_key: 表格列名，用于在日志中定位具体字段。
        percent_value: 表格中书写为百分号的原始数值。
    """
    if percent_value < 0.0 or percent_value > PERCENT_SCALE:
        print(
            f"[警告] {csv_key} = {percent_value} 超出百分比合理范围 "
            f"0~{PERCENT_SCALE:g}（表格中 5 表示 5%），导入后会被运行时钳制，请检查表格。"
        )


def percent_to_runtime(csv_key: str, text: str) -> str:
    """把表格中的百分比写法换算为运行时使用的 0~1 小数。

    参数:
        csv_key: 表格列名，用于判断该字段是否属于百分比字段。
        text: 表格单元格原始文本，例如 ``"5"`` 或 ``"0.0"``。
    返回:
        百分比字段返回换算后的十进制字符串（如 ``"0.05"``）；非百分比字段或无法解析时原样返回。
    """
    if csv_key not in PERCENT_STAT_KEYS:
        return text
    percent_value = _parse_stat_number(text)
    if percent_value is None:
        return text
    _warn_if_percent_out_of_range(csv_key, percent_value)
    return _format_stat_number(percent_value / PERCENT_SCALE)


def runtime_to_percent(csv_key: str, text: str) -> str:
    """把运行时小数换算回表格使用的百分比写法，保证双向同步稳定。

    参数:
        csv_key: 表格列名，用于判断该字段是否属于百分比字段。
        text: ``.tres`` 中的原始文本，例如 ``"0.05"``。
    返回:
        百分比字段返回乘以 100 后的十进制字符串（如 ``"5.0"``）；非百分比字段或无法解析时原样返回。
    """
    if csv_key not in PERCENT_STAT_KEYS:
        return text
    runtime_value = _parse_stat_number(text)
    if runtime_value is None:
        return text
    return _format_stat_number(runtime_value * PERCENT_SCALE)


def to_res_path(path: Path) -> str:
    """把磁盘路径转换为 Godot `res://` 路径。"""
    return "res://" + path.relative_to(ROOT).as_posix()


def to_disk_path(res_path: str) -> Path:
    """把 Godot `res://` 路径转换为磁盘路径。"""
    return (
        ROOT / res_path.removeprefix("res://")
        if hasattr(str, "removeprefix")
        else ROOT / res_path[6:]
    )


def write_text_atomically(path: Path, content: str, encoding: str = "utf-8") -> None:
    """以同目录临时文件加替换的方式写入文本，避免中断时截断原文件。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    file_descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", suffix=".tmp"
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(file_descriptor, "w", encoding=encoding, newline="") as file:
            file.write(content)
        os.replace(temporary_path, path)
    except OSError as error:
        raise CardTableSyncError(f"无法原子写入 {path.relative_to(ROOT)}：{error}") from error
    finally:
        if temporary_path.exists():
            temporary_path.unlink()


def create_resource_backup(paths: Iterable[Path]) -> Path | None:
    """备份本次将覆盖的已有资源，供同步后的人工回滚使用。"""
    existing_paths = sorted({path for path in paths if path.exists()})
    if not existing_paths:
        return None
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup_root = BACKUP_DIR / timestamp
    try:
        for source_path in existing_paths:
            target_path = backup_root / source_path.relative_to(ROOT)
            target_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_path, target_path)
    except OSError as error:
        raise CardTableSyncError(f"创建同步备份失败：{error}") from error
    _trim_old_backups()
    return backup_root


def _trim_old_backups() -> None:
    """限制自动备份数量，避免长期使用表格工具无限占用项目磁盘空间。"""
    if not BACKUP_DIR.exists():
        return
    backup_directories = sorted(
        (path for path in BACKUP_DIR.iterdir() if path.is_dir()),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    for expired_directory in backup_directories[BACKUP_RETENTION_COUNT:]:
        try:
            shutil.rmtree(expired_directory)
        except OSError as error:
            print(f"[警告] 无法清理过期同步备份 {expired_directory.name}：{error}")


def write_resource_batch_atomically(updates: dict[Path, str]) -> tuple[list[Path], Path | None]:
    """备份并逐文件原子提交资源更新；单个写入失败时恢复已提交的资源。"""
    if not updates:
        return [], None
    previous_existing_paths = {path for path in updates if path.exists()}
    backup_root = create_resource_backup(previous_existing_paths)
    applied_paths: list[Path] = []
    try:
        for path, content in updates.items():
            write_text_atomically(path, content)
            applied_paths.append(path)
    except CardTableSyncError as error:
        rollback_errors: list[str] = []
        for path in reversed(applied_paths):
            try:
                if path in previous_existing_paths and backup_root is not None:
                    backup_path = backup_root / path.relative_to(ROOT)
                    write_text_atomically(path, backup_path.read_text(encoding="utf-8"))
                elif path.exists():
                    path.unlink()
            except OSError as rollback_error:
                rollback_errors.append(f"{path.relative_to(ROOT)}：{rollback_error}")
        rollback_suffix = (
            "；回滚失败：" + "；".join(rollback_errors) if rollback_errors else ""
        )
        raise CardTableSyncError(f"资源写入失败，已尝试回滚：{error}{rollback_suffix}") from error
    return list(updates), backup_root


def godot_string(value: str) -> str:
    """生成 Godot `.tres` 可读的字符串字面量，保留中文并转义特殊字符。"""
    return json.dumps(value or "", ensure_ascii=False)


def godot_string_array(text: str) -> str:
    """把中英文分号分隔的 CSV 文本转换成 Godot `Array[String]` 字面量。"""
    values = [godot_string(value) for value in split_semicolon_values(text)]
    return "Array[String]([%s])" % ", ".join(values)


def string_or_null(value: str) -> str:
    """空字符串在 StringName 等字段中保持为 null，避免导出 `<null>` 噪音。"""
    return godot_string(value) if value else "null"


def safe_slug(text: str) -> str:
    """把任意文本转换成可作为资源文件名的稳定标识。"""
    slug = (text or "").strip().lower()
    slug = re.sub(r"[^0-9a-zA-Z_\-\u4e00-\u9fff]+", "_", slug)
    return slug.strip("_")


def get_csv_signature() -> dict[str, float]:
    """记录 CSV/XLSX 修改时间，用于判断外部表格是否被用户改动。"""
    return {
        "skill_csv": SKILL_CSV.stat().st_mtime if SKILL_CSV.exists() else 0.0,
        "monster_csv": MONSTER_CSV.stat().st_mtime if MONSTER_CSV.exists() else 0.0,
        "xlsx_file": XLSX_FILE.stat().st_mtime if XLSX_FILE.exists() else 0.0,
        "pending_xlsx_file": PENDING_XLSX_FILE.stat().st_mtime
        if PENDING_XLSX_FILE.exists()
        else 0.0,
    }


def _state_float(value: object) -> float:
    """把状态文件里的数字安全转换为浮点修改时间。"""
    if isinstance(value, (float, int, str)):
        return float(value)
    return 0.0


def read_sync_state() -> dict[str, float]:
    """读取上一次同步后的 CSV/XLSX 修改时间状态。"""
    if not STATE_FILE.exists():
        return {
            "skill_csv": 0.0,
            "monster_csv": 0.0,
            "xlsx_file": 0.0,
            "pending_xlsx_file": 0.0,
        }
    try:
        raw_data = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        if not isinstance(raw_data, dict):
            return {
                "skill_csv": 0.0,
                "monster_csv": 0.0,
                "xlsx_file": 0.0,
                "pending_xlsx_file": 0.0,
            }
        data = raw_data
    except json.JSONDecodeError:
        return {
            "skill_csv": 0.0,
            "monster_csv": 0.0,
            "xlsx_file": 0.0,
            "pending_xlsx_file": 0.0,
        }
    return {
        "skill_csv": _state_float(data.get("skill_csv", 0.0)),
        "monster_csv": _state_float(data.get("monster_csv", 0.0)),
        "xlsx_file": _state_float(data.get("xlsx_file", 0.0)),
        "pending_xlsx_file": _state_float(data.get("pending_xlsx_file", 0.0)),
    }


def write_sync_state() -> None:
    """写入当前 CSV/XLSX 修改时间，避免插件把自己刚导出的表格误判为外部改动。"""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_text_atomically(
        STATE_FILE,
        json.dumps(get_csv_signature(), ensure_ascii=False, indent=2),
    )


def csv_changed_since_last_sync() -> bool:
    """判断 CSV/XLSX 是否在上次同步后被外部编辑器修改。"""
    current = get_csv_signature()
    previous = read_sync_state()
    return any(current[key] > previous.get(key, 0.0) for key in current)


def get_latest_resource_time() -> float:
    """获取卡牌与怪物资源的最新修改时间。"""
    latest = 0.0
    for directory in [SKILL_CARD_DIR, COMBAT_SKILL_DIR, MONSTER_DIR]:
        if not directory.exists():
            continue
        for path in directory.rglob("*.tres"):
            latest = max(latest, path.stat().st_mtime)
    return latest


def read_text_with_csv_encoding(path: Path) -> str:
    """读取外部表格文本，兼容 Excel/WPS 常见的 UTF-8-BOM 与 GBK/GB18030 编码。"""
    data = path.read_bytes()
    for encoding in ["utf-8-sig", "utf-8", "gb18030"]:
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")


def read_csv_table(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    """读取 CSV 的表头和行数据，兼容 UTF-8、UTF-8-BOM、GBK/GB18030。"""
    if not path.exists():
        return [], []
    import io

    content = read_text_with_csv_encoding(path)
    reader = csv.DictReader(io.StringIO(content))
    return list(reader.fieldnames or []), [dict(row) for row in reader]


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    """读取 CSV 行数据，供只需要数据而不校验表头的兼容调用方使用。"""
    _headers, rows = read_csv_table(path)
    return rows


def write_csv_rows(path: Path, headers: list[str], rows: list[dict[str, str]]) -> Path:
    """原子写入 UTF-8-BOM CSV；被占用或无法替换时终止本次同步。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    file_descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", suffix=".tmp"
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(
            file_descriptor, "w", encoding="utf-8-sig", newline=""
        ) as file:
            writer = csv.DictWriter(file, fieldnames=headers)
            writer.writeheader()
            writer.writerows(rows)
        os.replace(temporary_path, path)
        return path
    except OSError as error:
        raise CardTableSyncError(f"无法写入 CSV 文件 {path.relative_to(ROOT)}：{error}") from error
    finally:
        if temporary_path.exists():
            temporary_path.unlink()


def element_to_label(value: str) -> str:
    """把资源中的五行枚举数字转换为表格中直接可读的中文名称。"""
    normalized = (value or "").strip()
    return ELEMENT_VALUE_TO_LABEL.get(normalized, normalized)


def element_to_value(value: str) -> str:
    """把表格中的中文五行名称转换回 Godot 资源需要的枚举数字。"""
    normalized = (value or "").strip()
    return ELEMENT_LABEL_TO_VALUE.get(normalized, normalized)


def targeting_to_label(value: str) -> str:
    """把资源中的目标枚举数字转换为表格中直接可读的中文名称。"""
    normalized = (value or "").strip()
    return TARGETING_VALUE_TO_LABEL.get(normalized, normalized)


def targeting_to_value(value: str) -> str:
    """把表格中的中文目标名称转换回 Godot 资源需要的枚举数字。"""
    normalized = (value or "").strip()
    return TARGETING_LABEL_TO_VALUE.get(normalized, normalized)


def split_semicolon_values(text: str) -> list[str]:
    """拆分中英文分号多选字段，过滤空白项并保持用户原有顺序。"""
    # 表格由中文用户手动维护时容易输入中文分号；导入时统一兼容，导出仍使用英文分号保持 CSV/XLSX 稳定。
    return [part.strip() for part in re.split(r"[;；]", text or "") if part.strip()]


def compact_semicolon_values(values: list[str]) -> str:
    """合并多选字段，去重后使用英文分号保存，便于 CSV 与 XLSX 双格式共用。"""
    result: list[str] = []
    for value in values:
        normalized = value.strip()
        if normalized and normalized not in result:
            result.append(normalized)
    return ";".join(result)


def normalize_skill_row_for_import(row: dict[str, str]) -> dict[str, str]:
    """把技能表的中文展示值转换为资源写入值。"""
    normalized = dict(row)
    normalized["element"] = element_to_value(normalized.get("element", ""))
    normalized["targeting_type"] = targeting_to_value(
        normalized.get("targeting_type", "")
    )
    return normalized


def normalize_monster_row_for_import(row: dict[str, str]) -> dict[str, str]:
    """把怪物表的中文五行展示值转换为资源写入值。"""
    normalized = dict(row)
    normalized["element"] = element_to_value(normalized.get("element", ""))
    return normalized


def xlsx_column_name(index: int) -> str:
    """把从 1 开始的列序号转换为 Excel 列名。"""
    name = ""
    while index:
        index, remainder = divmod(index - 1, 26)
        name = chr(65 + remainder) + name
    return name


def xlsx_cell_ref(row_index: int, column_index: int) -> str:
    """生成 Excel 单元格坐标。"""
    return f"{xlsx_column_name(column_index)}{row_index}"


def xlsx_text_cell(row_index: int, column_index: int, value: str) -> str:
    """生成 XLSX inlineStr 单元格，避免依赖 sharedStrings 文件。"""
    ref = xlsx_cell_ref(row_index, column_index)
    escaped = html.escape(value or "")
    return f'<c r="{ref}" t="inlineStr"><is><t>{escaped}</t></is></c>'


def xlsx_sheet_xml(
    rows: list[dict[str, str]],
    headers: list[str],
    validations: dict[str, str] | None = None,
) -> str:
    """生成工作表 XML，并把需要人工输入的字段设置为下拉列表。"""
    sheet_rows: list[str] = []
    header_cells = [
        xlsx_text_cell(1, index, header) for index, header in enumerate(headers, 1)
    ]
    sheet_rows.append('<row r="1">' + "".join(header_cells) + "</row>")
    for row_index, row in enumerate(rows, 2):
        cells = [
            xlsx_text_cell(row_index, column_index, row.get(header, ""))
            for column_index, header in enumerate(headers, 1)
        ]
        sheet_rows.append(f'<row r="{row_index}">' + "".join(cells) + "</row>")
    validation_xml = ""
    if validations:
        validation_items: list[str] = []
        max_row = max(len(rows) + 200, 200)
        for header, formula in validations.items():
            if header not in headers:
                continue
            column = xlsx_column_name(headers.index(header) + 1)
            sqref = f"{column}2:{column}{max_row}"
            validation_items.append(
                '<dataValidation type="list" allowBlank="1" showErrorMessage="1" '
                f'sqref="{sqref}"><formula1>{html.escape(formula)}</formula1></dataValidation>'
            )
        if validation_items:
            validation_xml = (
                f'<dataValidations count="{len(validation_items)}">'
                + "".join(validation_items)
                + "</dataValidations>"
            )
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        "<sheetData>"
        + "".join(sheet_rows)
        + "</sheetData>"
        + validation_xml
        + "</worksheet>"
    )


def xlsx_is_writable(path: Path) -> bool:
    """检测 XLSX 是否可写；Excel/WPS 打开文件时 Windows 会拒绝写入。"""
    if not path.exists():
        return True
    try:
        with path.open("r+b"):
            return True
    except PermissionError:
        return False


def promote_pending_xlsx() -> bool:
    """当主 XLSX 解锁后，把之前生成的待应用工作簿替换回主文件。"""
    if not PENDING_XLSX_FILE.exists():
        return False
    if not xlsx_is_writable(XLSX_FILE):
        print(
            f"XLSX 仍被外部程序占用，待应用文件保留在：{PENDING_XLSX_FILE.relative_to(ROOT)}"
        )
        return False
    if (
        XLSX_FILE.exists()
        and XLSX_FILE.stat().st_mtime > PENDING_XLSX_FILE.stat().st_mtime
    ):
        PENDING_XLSX_FILE.unlink()
        print("主 XLSX 比待应用文件更新，已丢弃过期待应用文件。")
        return False
    PENDING_XLSX_FILE.replace(XLSX_FILE)
    print(f"已把待应用 XLSX 更新到：{XLSX_FILE.relative_to(ROOT)}")
    return True


def build_options_rows() -> list[dict[str, str]]:
    """生成隐藏选项表，为 Excel/WPS 下拉框提供稳定数据源。"""
    rows: list[dict[str, str]] = []
    max_count = max(len(ELEMENT_LABEL_OPTIONS), len(TARGETING_LABEL_OPTIONS))
    for index in range(max_count):
        rows.append(
            {
                "element_options": ELEMENT_LABEL_OPTIONS[index]
                if index < len(ELEMENT_LABEL_OPTIONS)
                else "",
                "targeting_type_options": TARGETING_LABEL_OPTIONS[index]
                if index < len(TARGETING_LABEL_OPTIONS)
                else "",
            }
        )
    return rows


def write_xlsx_workbook(
    skill_rows: list[dict[str, str]],
    monster_rows: list[dict[str, str]],
) -> Path:
    """原子导出带下拉框的 XLSX，并在主工作簿锁定时写入 pending 文件。"""
    temporary_path: Path | None = None
    try:
        promote_pending_xlsx()
        option_rows = build_options_rows()
        target_file = XLSX_FILE if xlsx_is_writable(XLSX_FILE) else PENDING_XLSX_FILE
        if target_file == PENDING_XLSX_FILE:
            print(
                f"XLSX 文件正在被外部程序占用，本次导出写入待应用文件：{PENDING_XLSX_FILE.relative_to(ROOT)}"
            )
        file_descriptor, temporary_name = tempfile.mkstemp(
            dir=target_file.parent, prefix=f".{target_file.name}.", suffix=".tmp"
        )
        os.close(file_descriptor)
        temporary_path = Path(temporary_name)
        with zipfile.ZipFile(temporary_path, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(
                "[Content_Types].xml",
                '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                '<Default Extension="xml" ContentType="application/xml"/>'
                '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
                '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
                '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
                '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
                '<Override PartName="/xl/worksheets/sheet3.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
                "</Types>",
            )
            archive.writestr(
                "_rels/.rels",
                '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
                "</Relationships>",
            )
            archive.writestr(
                "xl/workbook.xml",
                '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
                "<sheets>"
                '<sheet name="skill_cards" sheetId="1" r:id="rId1"/>'
                '<sheet name="monster_cards" sheetId="2" r:id="rId2"/>'
                '<sheet name="Options" sheetId="3" state="hidden" r:id="rId3"/>'
                "</sheets></workbook>",
            )
            archive.writestr(
                "xl/_rels/workbook.xml.rels",
                '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
                '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>'
                '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet3.xml"/>'
                '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
                "</Relationships>",
            )
            archive.writestr(
                "xl/styles.xml",
                '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
                '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
                '<fills count="1"><fill><patternFill patternType="none"/></fill></fills>'
                '<borders count="1"><border/></borders>'
                '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
                '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
                "</styleSheet>",
            )
            archive.writestr(
                "xl/worksheets/sheet1.xml",
                xlsx_sheet_xml(
                    skill_rows,
                    SKILL_HEADERS,
                    {
                        "element": "Options!$A$2:$A$7",
                        "targeting_type": "Options!$B$2:$B$8",
                    },
                ),
            )
            archive.writestr(
                "xl/worksheets/sheet2.xml",
                xlsx_sheet_xml(
                    monster_rows,
                    MONSTER_HEADERS,
                    {"element": "Options!$A$2:$A$7"},
                ),
            )
            archive.writestr(
                "xl/worksheets/sheet3.xml",
                xlsx_sheet_xml(
                    option_rows,
                    [
                        "element_options",
                        "targeting_type_options",
                    ],
                ),
            )
        os.replace(temporary_path, target_file)
        return target_file
    except (OSError, zipfile.BadZipFile) as error:
        raise CardTableSyncError(
            f"无法写入 XLSX 文件 {XLSX_FILE.relative_to(ROOT)}：{error}"
        ) from error
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()


def get_xlsx_shared_strings(archive: zipfile.ZipFile) -> list[str]:
    """读取 Excel/WPS 保存后生成的 sharedStrings，保证手工编辑后的 XLSX 仍能被导入。"""
    if "xl/sharedStrings.xml" not in archive.namelist():
        return []
    namespace = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
    root = ElementTree.fromstring(archive.read("xl/sharedStrings.xml"))
    values: list[str] = []
    for item in root.findall(f"{namespace}si"):
        # Excel 可能把一个单元格拆成多个富文本片段；这里合并所有 t 节点才是用户看到的完整文本。
        values.append(
            "".join(node.text or "" for node in item.findall(f".//{namespace}t"))
        )
    return values


def get_xlsx_cell_text(
    cell: ElementTree.Element, shared_strings: list[str] | None = None
) -> str:
    """读取 XLSX 单元格文本，兼容 inlineStr、sharedStrings 与普通 v 节点。"""
    namespace = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
    if cell.attrib.get("t") == "s":
        value = cell.find(f"{namespace}v")
        if value is None or value.text is None:
            return ""
        try:
            return (shared_strings or [])[int(value.text)]
        except (IndexError, ValueError):
            return ""
    inline_texts = cell.findall(f"{namespace}is/{namespace}t")
    if inline_texts:
        return "".join(node.text or "" for node in inline_texts)
    value = cell.find(f"{namespace}v")
    return value.text if value is not None and value.text is not None else ""


def read_xlsx_sheet_table(sheet_path: str) -> tuple[list[str], list[dict[str, str]]]:
    """读取 XLSX 工作表的表头和行数据，供预检与导入共同使用。"""
    if not XLSX_FILE.exists():
        return [], []
    namespace = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
    with zipfile.ZipFile(XLSX_FILE) as archive:
        shared_strings = get_xlsx_shared_strings(archive)
        root = ElementTree.fromstring(archive.read(sheet_path))
    rows: list[list[str]] = []
    for row_node in root.findall(f".//{namespace}row"):
        values: dict[int, str] = {}
        max_column = 0
        for cell in row_node.findall(f"{namespace}c"):
            ref = cell.attrib.get("r", "A1")
            column_letters = re.sub(r"\d+", "", ref)
            column_index = 0
            for letter in column_letters:
                column_index = column_index * 26 + ord(letter.upper()) - 64
            values[column_index] = get_xlsx_cell_text(cell, shared_strings)
            max_column = max(max_column, column_index)
        rows.append([values.get(index, "") for index in range(1, max_column + 1)])
    if not rows:
        return [], []
    headers = rows[0]
    result: list[dict[str, str]] = []
    for values in rows[1:]:
        if not any(value.strip() for value in values):
            continue
        result.append(
            {
                header: values[index] if index < len(values) else ""
                for index, header in enumerate(headers)
                if header
            }
        )
    return headers, result


def read_card_tables() -> tuple[
    list[str], list[dict[str, str]], list[str], list[dict[str, str]], str
]:
    """优先读取被用户改过的 XLSX；返回表头、行数据与实际使用的来源。"""
    previous = read_sync_state()
    xlsx_time = XLSX_FILE.stat().st_mtime if XLSX_FILE.exists() else 0.0
    csv_time = max(
        SKILL_CSV.stat().st_mtime if SKILL_CSV.exists() else 0.0,
        MONSTER_CSV.stat().st_mtime if MONSTER_CSV.exists() else 0.0,
    )
    # 用户手动保存 XLSX 后，Excel/WPS 可能同时触发 CSV 时间落后或接近；用上次同步状态判断更可靠。
    if XLSX_FILE.exists() and (
        xlsx_time > previous.get("xlsx_file", 0.0) or xlsx_time >= csv_time
    ):
        print(f"正在读取 XLSX 表格：{XLSX_FILE.relative_to(ROOT)}")
        skill_headers, skill_rows = read_xlsx_sheet_table("xl/worksheets/sheet1.xml")
        monster_headers, monster_rows = read_xlsx_sheet_table("xl/worksheets/sheet2.xml")
        return (
            skill_headers,
            skill_rows,
            monster_headers,
            monster_rows,
            "XLSX",
        )
    print("正在读取 CSV 表格。")
    skill_headers, skill_rows = read_csv_table(SKILL_CSV)
    monster_headers, monster_rows = read_csv_table(MONSTER_CSV)
    return skill_headers, skill_rows, monster_headers, monster_rows, "CSV"


def parse_resource_paths(text: str) -> dict[str, str]:
    """解析 `.tres` 中 ExtResource id 到资源路径的映射。"""
    resources: dict[str, str] = {}
    for match in re.finditer(
        r'\[ext_resource[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"', text
    ):
        resources[match.group(2)] = match.group(1)
    return resources


def get_resource_block(text: str) -> tuple[str, str]:
    """拆分 `.tres` 头部与唯一的 `[resource]` 块，避免把子资源字段误当作根资源字段。"""
    resource_match = re.search(r"^\[resource\]\s*$", text, flags=re.MULTILINE)
    if resource_match is None:
        raise CardTableSyncError("资源文件缺少 [resource] 块，已拒绝修改以保护原始数据。")
    return text[: resource_match.end()], text[resource_match.end() :]


def parse_scalar_in_block(text: str, key: str, default: str = "") -> str:
    """读取指定资源块中的简单标量字段。"""
    match = re.search(rf"^{re.escape(key)}\s*=\s*(.+)$", text, flags=re.MULTILINE)
    if not match:
        return default
    value = match.group(1).strip()
    if value == "null":
        return ""
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        # `.tres` 字符串本身已经按 UTF-8 读取，使用 literal_eval 只处理引号与转义字符，避免中文被二次解码成乱码。
        try:
            literal_value = cast(object, ast.literal_eval(value))
            return str(literal_value)
        except (SyntaxError, ValueError):
            return value[1:-1]
    return value


def parse_scalar(text: str, key: str, default: str = "") -> str:
    """读取 `.tres` 根资源段里的简单标量字段。"""
    _header, resource_block = get_resource_block(text)
    return parse_scalar_in_block(resource_block, key, default)


def parse_scalar_in_subresource(
    text: str, sub_id: str, key: str, default: str = ""
) -> str:
    """读取 .tres 中指定子资源块内的标量字段，避免文件内多子资源重名键的歧义。"""
    block_pattern = (
        r'\[sub_resource[^\]]*id="'
        + re.escape(sub_id)
        + r'"[^\]]*\][\s\S]*?(?=\n\[(?:sub_resource|resource|ext_resource)|\Z)'
    )
    block_match = re.search(block_pattern, text)
    if not block_match:
        return default
    return parse_scalar_in_block(block_match.group(0), key, default)


def parse_ext_assignment(text: str, key: str, resources: dict[str, str]) -> str:
    """读取 `Skill = ExtResource("...")` 这类资源引用字段。"""
    _header, resource_block = get_resource_block(text)
    match = re.search(
        rf"^{re.escape(key)}\s*=\s*ExtResource\(\"([^\"]+)\"\)",
        resource_block,
        flags=re.MULTILINE,
    )
    if not match:
        return ""
    return resources.get(match.group(1), "")


def parse_array_strings(text: str, key: str) -> str:
    """读取 `Array[String](["a", "b"])` 并用分号输出，适配 CSV 中的多值字段。"""
    _header, resource_block = get_resource_block(text)
    match = re.search(
        rf"^{re.escape(key)}\s*=\s*Array\[String\]\(\[(.*)\]\)",
        resource_block,
        flags=re.MULTILINE,
    )
    if not match:
        return ""
    return ";".join(re.findall(r'"([^"]*)"', match.group(1)))


def get_combat_skill_basics(path: str) -> tuple[str, str, str]:
    """读取战斗技能资源的元素、目标类型和技能名，无法读取时返回空值。"""
    if not path.startswith("res://"):
        return "", "", ""
    file_path = to_disk_path(path)
    if not file_path.exists():
        return "", "", ""
    text = file_path.read_text(encoding="utf-8")
    return (
        parse_scalar(text, "Element"),
        parse_scalar(text, "TargetingType"),
        parse_scalar(text, "CardName"),
    )


def replace_or_add_resource_property(text: str, key: str, value_literal: str) -> str:
    """替换 `[resource]` 段中的属性；不存在时追加到资源段末尾。"""
    pattern = rf"^{re.escape(key)}\s*=\s*.*$"
    replacement = f"{key} = {value_literal}"
    header, resource_block = get_resource_block(text)
    if re.search(pattern, resource_block, flags=re.MULTILINE):
        updated_block = re.sub(
            pattern, replacement, resource_block, count=1, flags=re.MULTILINE
        )
        return header + updated_block
    return header + resource_block.rstrip() + "\n" + replacement + "\n"


def replace_or_add_line(text: str, key: str, value_literal: str) -> str:
    """替换任意位置的单行属性；不存在时追加到文件末尾。"""
    pattern = rf"^{re.escape(key)}\s*=\s*.*$"
    replacement = f"{key} = {value_literal}"
    if re.search(pattern, text, flags=re.MULTILINE):
        return re.sub(pattern, replacement, text, count=1, flags=re.MULTILINE)
    return text.rstrip() + "\n" + replacement + "\n"


def ensure_ext_resource(
    text: str, resource_type: str, path: str, resource_id: str
) -> str:
    """确保 `.tres` 中存在指定 ExtResource 声明。"""
    text = remove_ext_resource_by_id(text, resource_id)
    line = f'[ext_resource type="{resource_type}" path="{path}" id="{resource_id}"]\n'
    insert_at = text.find("[sub_resource")
    if insert_at < 0:
        insert_at = text.find("[resource]")
    if insert_at < 0:
        return text.rstrip() + "\n" + line
    return text[:insert_at] + line + text[insert_at:]


def remove_ext_resource_by_id(text: str, resource_id_prefix: str) -> str:
    """移除指定 id 或 id 前缀的 ExtResource 行，用于重复导入时覆盖 CSV 生成的引用。"""
    return re.sub(
        rf'^\[ext_resource[^\]]*id="{re.escape(resource_id_prefix)}[^"\]]*"[^\]]*\]\n?',
        "",
        text,
        flags=re.MULTILINE,
    )


def strip_csv_subresources(text: str) -> str:
    """移除上一次 CSV 导入生成的怪物技能与属性子资源，避免重复堆叠。"""
    pattern = r'\n?\[sub_resource[^\]]*id="CSV_[^"]+"\][\s\S]*?(?=\n\[(?:sub_resource|resource|ext_resource)|\Z)'
    return re.sub(pattern, "\n", text)


def collect_monster_skill_map() -> tuple[
    dict[str, list[str]], dict[str, list[str]], dict[str, str]
]:
    """扫描怪物技能集合，同时生成技能拥有者映射和怪物技能列表。"""
    owners: dict[str, list[str]] = {}
    monster_skills: dict[str, list[str]] = {}
    monster_names: dict[str, str] = {}
    for path in sorted(MONSTER_DIR.glob("*.tres")):
        text = path.read_text(encoding="utf-8")
        resources = parse_resource_paths(text)
        res_path = to_res_path(path)
        monster_names[res_path] = parse_scalar(text, "MonsterName")
        skill_paths = sorted(
            {
                value
                for value in resources.values()
                if value.startswith("res://resources/combat_skills/")
            }
        )
        monster_skills[res_path] = skill_paths
        for skill_path in skill_paths:
            owners.setdefault(skill_path, []).append(res_path)
    return owners, monster_skills, monster_names


def build_skill_key_map() -> dict[str, str]:
    """建立技能卡路径、战斗技能路径、文件名、卡名到战斗技能路径的索引。"""
    key_map: dict[str, str] = {}
    for path in sorted(SKILL_CARD_DIR.glob("*.tres")):
        text = path.read_text(encoding="utf-8")
        resources = parse_resource_paths(text)
        card_path = to_res_path(path)
        combat_path = parse_ext_assignment(text, "Skill", resources)
        card_name = parse_scalar(text, "CardName")
        for key in [card_path, path.stem, card_name, combat_path]:
            if key:
                key_map[key] = combat_path
    for path in sorted(COMBAT_SKILL_DIR.glob("*.tres")):
        text = path.read_text(encoding="utf-8")
        skill_path = to_res_path(path)
        skill_name = parse_scalar(text, "CardName")
        for key in [skill_path, path.stem, skill_name]:
            if key:
                key_map[key] = skill_path
    return key_map


def build_monster_key_map(rows: list[dict[str, str]] | None = None) -> dict[str, str]:
    """建立怪物路径、文件名、怪物名到怪物资源路径的索引。"""
    key_map: dict[str, str] = {}
    for path in sorted(MONSTER_DIR.glob("*.tres")):
        text = path.read_text(encoding="utf-8")
        res_path = to_res_path(path)
        monster_name = parse_scalar(text, "MonsterName")
        for key in [res_path, path.stem, monster_name, f"{monster_name} | {res_path}"]:
            if key:
                key_map[key] = res_path
    for row in rows or []:
        path = resolve_monster_path(row)
        for key in [
            row.get("resource_path", ""),
            row.get("id_slug", ""),
            row.get("monster_name", ""),
            f"{row.get('monster_name', '')} | {path}"
            if row.get("monster_name", "")
            else "",
        ]:
            if key:
                key_map[key] = path
    return key_map


def resolve_skill_card_path(row: dict[str, str]) -> str:
    """根据 CSV 行解析技能卡资源路径，新增行用 id_slug 自动生成。"""
    explicit = (row.get("resource_path") or "").strip()
    if explicit:
        return explicit
    slug = safe_slug(
        row.get("id_slug") or row.get("card_id") or row.get("card_name") or ""
    )
    return f"res://resources/skill_cards/{slug}.tres" if slug else ""


def resolve_combat_skill_path(row: dict[str, str], skill_card_path: str) -> str:
    """根据 CSV 行解析战斗技能资源路径，新增行默认与技能卡同名。"""
    explicit = (row.get("combat_skill_path") or "").strip()
    if explicit:
        return explicit
    slug = (
        Path(skill_card_path).stem
        if skill_card_path
        else safe_slug(row.get("id_slug") or row.get("card_name") or "")
    )
    return f"res://resources/combat_skills/{slug}.tres" if slug else ""


def resolve_monster_path(row: dict[str, str]) -> str:
    """根据 CSV 行解析怪物资源路径；id_slug 始终由最终资源文件名派生。"""
    explicit = (row.get("resource_path") or "").strip()
    if explicit:
        return explicit
    slug = safe_slug(row.get("id_slug") or row.get("monster_name") or "")
    return f"res://resources/monster/{slug}.tres" if slug else ""


def derive_id_slug_from_path(res_path: str, fallback: str = "") -> str:
    """从资源路径文件名生成 id_slug，确保表格 id 与 `.tres` 文件名保持一致。"""
    if res_path:
        return Path(res_path).stem
    return safe_slug(fallback)


def validate_managed_resource_path(
    res_path: str, managed_directory: Path, field_name: str, errors: list[str]
) -> Path | None:
    """校验表格资源路径只能落在指定目录，阻断路径穿越与误写项目其它文件。"""
    normalized_path = (res_path or "").strip()
    if not normalized_path.startswith("res://"):
        errors.append(f"{field_name} 必须使用 res:// 路径：{normalized_path or '<空>'}")
        return None
    path_parts = Path(normalized_path.removeprefix("res://")).parts
    if ".." in path_parts:
        errors.append(f"{field_name} 不允许包含路径穿越段：{normalized_path}")
        return None
    if "\\" in normalized_path or not normalized_path.endswith(".tres"):
        errors.append(f"{field_name} 必须是受管目录内的 .tres 文件：{normalized_path}")
        return None
    candidate_path = (ROOT / normalized_path.removeprefix("res://")).resolve()
    allowed_root = managed_directory.resolve()
    try:
        candidate_path.relative_to(allowed_root)
    except ValueError:
        errors.append(f"{field_name} 越出受管目录，已拒绝写入：{normalized_path}")
        return None
    return candidate_path


def validate_optional_resource_reference(
    res_path: str, field_name: str, errors: list[str]
) -> None:
    """校验可选的场景、图标等引用路径，避免把无效引用写进 `.tres`。"""
    normalized_path = (res_path or "").strip()
    if not normalized_path:
        return
    path_parts = Path(normalized_path.removeprefix("res://")).parts
    if ".." in path_parts:
        errors.append(f"{field_name} 不允许包含路径穿越段：{normalized_path}")
        return
    if not normalized_path.startswith("res://") or "\\" in normalized_path:
        errors.append(f"{field_name} 必须使用 res:// 路径：{normalized_path}")
        return
    candidate_path = (ROOT / normalized_path.removeprefix("res://")).resolve()
    try:
        candidate_path.relative_to(ROOT.resolve())
    except ValueError:
        errors.append(f"{field_name} 越出项目目录，已拒绝引用：{normalized_path}")
        return
    if not candidate_path.exists():
        errors.append(f"{field_name} 指向的文件不存在：{normalized_path}")


def validate_number(
    text: str,
    field_name: str,
    errors: list[str],
    minimum: float | None = None,
    integer_only: bool = False,
) -> None:
    """校验表格数值的有限性、范围和整数要求，避免生成 Godot 无法解析的字面量。"""
    normalized_text = (text or "").strip()
    if not normalized_text:
        return
    value = _parse_stat_number(normalized_text)
    if value is None or not math.isfinite(value):
        errors.append(f"{field_name} 必须是有限数值，当前为：{normalized_text}")
        return
    if integer_only and not value.is_integer():
        errors.append(f"{field_name} 必须是整数，当前为：{normalized_text}")
    if minimum is not None and value < minimum:
        errors.append(f"{field_name} 不能小于 {minimum:g}，当前为：{normalized_text}")


def validate_id_slug(text: str, field_name: str, errors: list[str]) -> None:
    """校验新增资源使用稳定文件名标识，避免导入时静默改名或创建异常路径。"""
    normalized_text = (text or "").strip()
    if not normalized_text:
        errors.append(f"{field_name} 不能为空。")
        return
    if safe_slug(normalized_text) != normalized_text:
        errors.append(f"{field_name} 只能包含中英文、数字、下划线或连字符：{normalized_text}")


def build_future_skill_key_map(rows: list[dict[str, str]]) -> dict[str, str]:
    """把本次新增或改名的技能加入索引，供同批怪物引用在预检阶段解析。"""
    key_map = build_skill_key_map()
    for row in rows:
        skill_card_path = resolve_skill_card_path(row)
        combat_path = resolve_combat_skill_path(row, skill_card_path)
        for key in [
            skill_card_path,
            Path(skill_card_path).stem if skill_card_path else "",
            row.get("id_slug", ""),
            row.get("card_name", ""),
            combat_path,
            Path(combat_path).stem if combat_path else "",
        ]:
            if key:
                key_map[key] = combat_path
    return key_map


def validate_table_headers(
    headers: list[str], expected_headers: list[str], table_name: str, errors: list[str]
) -> None:
    """校验表格保留全部受支持列，防止误删列后以空值覆盖现有资源。"""
    missing_headers = [header for header in expected_headers if header not in headers]
    if missing_headers:
        errors.append(f"{table_name} 缺少列：{', '.join(missing_headers)}")
    duplicated_headers = sorted(
        {header for header in headers if header and headers.count(header) > 1}
    )
    if duplicated_headers:
        errors.append(f"{table_name} 存在重复列：{', '.join(duplicated_headers)}")


def validate_import_rows(
    skill_headers: list[str],
    skill_rows_raw: list[dict[str, str]],
    monster_headers: list[str],
    monster_rows_raw: list[dict[str, str]],
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    """完整预检两张表；发现任意错误时抛出异常，保证后续不会改写资源。"""
    skill_rows = [normalize_skill_row_for_import(row) for row in skill_rows_raw]
    monster_rows = [normalize_monster_row_for_import(row) for row in monster_rows_raw]
    errors: list[str] = []
    skill_paths: set[Path] = set()
    combat_paths: set[Path] = set()
    skill_names: set[str] = set()
    monster_paths: set[Path] = set()
    monster_names: set[str] = set()

    validate_table_headers(skill_headers, SKILL_HEADERS, "技能表", errors)
    validate_table_headers(monster_headers, MONSTER_HEADERS, "怪物表", errors)

    for row_index, row in enumerate(skill_rows, start=2):
        row_label = f"技能表第 {row_index} 行"
        resource_path = (row.get("resource_path") or "").strip()
        id_slug = (row.get("id_slug") or "").strip()
        if not resource_path:
            validate_id_slug(id_slug, f"{row_label} id_slug", errors)
        if not (row.get("card_name") or "").strip():
            errors.append(f"{row_label} card_name 不能为空。")
        skill_card_path = resolve_skill_card_path(row)
        combat_skill_path = resolve_combat_skill_path(row, skill_card_path)
        validated_skill_path = validate_managed_resource_path(
            skill_card_path, SKILL_CARD_DIR, f"{row_label} resource_path", errors
        )
        validated_combat_path = validate_managed_resource_path(
            combat_skill_path, COMBAT_SKILL_DIR, f"{row_label} combat_skill_path", errors
        )
        if validated_skill_path is not None:
            if validated_skill_path in skill_paths:
                errors.append(f"{row_label} resource_path 与其它技能重复：{skill_card_path}")
            skill_paths.add(validated_skill_path)
        if validated_combat_path is not None:
            if validated_combat_path in combat_paths:
                errors.append(
                    f"{row_label} combat_skill_path 与其它技能重复：{combat_skill_path}"
                )
            combat_paths.add(validated_combat_path)
        card_name = (row.get("card_name") or "").strip()
        if card_name:
            if card_name in skill_names:
                errors.append(f"{row_label} card_name 与其它技能重复：{card_name}")
            skill_names.add(card_name)
        if (row.get("element") or "") and (row.get("element") or "") not in ELEMENT_VALUE_TO_LABEL:
            errors.append(f"{row_label} element 不是支持的五行值。")
        if (row.get("targeting_type") or "") and (
            row.get("targeting_type") or ""
        ) not in TARGETING_VALUE_TO_LABEL:
            errors.append(f"{row_label} targeting_type 不是支持的目标类型。")
        validate_number(row.get("cost") or "", f"{row_label} cost", errors, 0, True)
        validate_optional_resource_reference(row.get("icon_path") or "", f"{row_label} icon_path", errors)

    for row_index, row in enumerate(monster_rows, start=2):
        row_label = f"怪物表第 {row_index} 行"
        resource_path = (row.get("resource_path") or "").strip()
        id_slug = (row.get("id_slug") or "").strip()
        if not resource_path:
            validate_id_slug(id_slug, f"{row_label} id_slug", errors)
        monster_name = (row.get("monster_name") or "").strip()
        if not monster_name:
            errors.append(f"{row_label} monster_name 不能为空。")
        monster_path = resolve_monster_path(row)
        validated_monster_path = validate_managed_resource_path(
            monster_path, MONSTER_DIR, f"{row_label} resource_path", errors
        )
        if validated_monster_path is not None:
            if validated_monster_path in monster_paths:
                errors.append(f"{row_label} resource_path 与其它怪物重复：{monster_path}")
            monster_paths.add(validated_monster_path)
        if monster_name:
            if monster_name in monster_names:
                errors.append(f"{row_label} monster_name 与其它怪物重复：{monster_name}")
            monster_names.add(monster_name)
        if (row.get("element") or "") and (row.get("element") or "") not in ELEMENT_VALUE_TO_LABEL:
            errors.append(f"{row_label} element 不是支持的五行值。")
        validate_number(row.get("faction") or "", f"{row_label} faction", errors, 0, True)
        faction_value = _parse_stat_number(row.get("faction") or "")
        if faction_value is not None and faction_value not in {0.0, 1.0, 2.0}:
            errors.append(f"{row_label} faction 只能是 0、1 或 2。")
        validate_optional_resource_reference(
            row.get("model_scene_path") or "", f"{row_label} model_scene_path", errors
        )
        validate_optional_resource_reference(
            row.get("behavior_tree_scene_path") or "",
            f"{row_label} behavior_tree_scene_path",
            errors,
        )
        for csv_key, _gd_key, _default_value in BASE_STAT_FIELDS:
            validate_number(row.get(csv_key) or "", f"{row_label} {csv_key}", errors)
            if csv_key in PERCENT_STAT_KEYS:
                percent_value = _parse_stat_number(row.get(csv_key) or "")
                if percent_value is not None and not 0.0 <= percent_value <= PERCENT_SCALE:
                    errors.append(
                        f"{row_label} {csv_key} 必须在 0~{PERCENT_SCALE:g} 之间。"
                    )

    skill_key_map = build_future_skill_key_map(skill_rows)
    monster_key_map = build_monster_key_map(monster_rows)
    for row_index, row in enumerate(skill_rows, start=2):
        for owner in split_semicolon_values(row.get("monster_owners") or ""):
            if owner not in monster_key_map:
                errors.append(f"技能表第 {row_index} 行 monster_owners 包含未知怪物：{owner}")
    for row_index, row in enumerate(monster_rows, start=2):
        for skill_name in split_semicolon_values(row.get("skill_names") or ""):
            if skill_name not in skill_key_map:
                errors.append(f"怪物表第 {row_index} 行 skill_names 包含未知技能：{skill_name}")

    if errors:
        preview = "\n".join(f"- {error}" for error in errors[:20])
        remaining = len(errors) - 20
        suffix = f"\n- 另有 {remaining} 项错误。" if remaining > 0 else ""
        raise CardTableValidationError(f"表格预检失败，共 {len(errors)} 项：\n{preview}{suffix}")
    return skill_rows, monster_rows


def resolve_skill_paths(text: str, key_map: dict[str, str]) -> list[str]:
    """解析中英文分号分隔的技能路径/名称，统一转换为 CombatSkillData 路径。"""
    result: list[str] = []
    for token in split_semicolon_values(text):
        path = key_map.get(token, token)
        if path and path not in result:
            result.append(path)
    return result


def normalize_name_list(text: str) -> list[str]:
    """标准化中文名称列表，用于判断表格技能名是否真的被用户改动。"""
    return split_semicolon_values(text)


def get_current_monster_skill_names(monster_path: str) -> list[str]:
    """从现有怪物资源读取当前技能中文名，避免未改动的导出列误覆盖技能归属配置。"""
    if not monster_path.startswith("res://"):
        return []
    file_path = to_disk_path(monster_path)
    if not file_path.exists():
        return []
    text = file_path.read_text(encoding="utf-8")
    resources = parse_resource_paths(text)
    skill_paths = sorted(
        {
            value
            for value in resources.values()
            if value.startswith("res://resources/combat_skills/")
        }
    )
    return [get_combat_skill_basics(skill_path)[2] for skill_path in skill_paths]


def skill_names_were_edited(monster_path: str, skill_names_text: str) -> bool:
    """判断怪物表 skill_names 是否被用户手动改过；改过时它对技能池拥有最高优先级。"""
    if not skill_names_text.strip():
        return False
    return normalize_name_list(skill_names_text) != get_current_monster_skill_names(
        monster_path
    )


def export_skill_csv(
    owners: dict[str, list[str]], monster_names: dict[str, str]
) -> list[dict[str, str]]:
    """导出玩家技能卡表。"""
    rows: list[dict[str, str]] = []
    for path in sorted(SKILL_CARD_DIR.glob("*.tres")):
        text = path.read_text(encoding="utf-8")
        resources = parse_resource_paths(text)
        res_path = to_res_path(path)
        combat_path = parse_ext_assignment(text, "Skill", resources)
        element, targeting_type, _skill_name = get_combat_skill_basics(combat_path)
        rows.append(
            {
                "resource_path": res_path,
                "id_slug": path.stem,
                "card_id": parse_scalar(text, "CardId"),
                "card_name": parse_scalar(text, "CardName"),
                "description": parse_scalar(text, "Description"),
                "icon_path": parse_ext_assignment(text, "CardIcon", resources),
                "cost": parse_scalar(text, "cost", "10"),
                "tags": parse_array_strings(text, "CardTags"),
                "combat_skill_path": combat_path,
                "element": element_to_label(element),
                "targeting_type": targeting_to_label(targeting_type),
                "monster_owners": ";".join(
                    [
                        monster_names.get(owner, owner)
                        for owner in owners.get(combat_path, [])
                    ]
                ),
            }
        )
    write_csv_rows(SKILL_CSV, SKILL_HEADERS, rows)
    return rows


def export_monster_csv(monster_skills: dict[str, list[str]]) -> list[dict[str, str]]:
    """导出怪物卡表。"""
    rows: list[dict[str, str]] = []
    for path in sorted(MONSTER_DIR.glob("*.tres")):
        text = path.read_text(encoding="utf-8")
        resources = parse_resource_paths(text)
        res_path = to_res_path(path)
        skill_paths = monster_skills.get(res_path, [])
        skill_names = [
            get_combat_skill_basics(skill_path)[2] for skill_path in skill_paths
        ]
        row = {
            "resource_path": res_path,
            "id_slug": derive_id_slug_from_path(res_path, path.stem),
            "monster_name": parse_scalar(text, "MonsterName"),
            "element": element_to_label(parse_scalar(text, "ElementalProperty")),
            "faction": parse_scalar(text, "Faction", "0"),
            "model_scene_path": parse_ext_assignment(text, "ModelScene", resources),
            "behavior_tree_scene_path": parse_ext_assignment(
                text, "BehaviorTreeScene", resources
            ),
            "skill_names": ";".join(skill_names),
        }
        # 从 CSV_StartingStats 子资源块读取属性，避免受文件中其他子资源同名键干扰（如 Godot Inspector 创建的旧 Resource_stats）
        has_csv_stats = bool(
            re.search(r'\[sub_resource[^\]]*id="CSV_StartingStats"[^\]]*\]', text)
        )
        for csv_key, gd_key, default_value in BASE_STAT_FIELDS:
            raw = (
                parse_scalar_in_subresource(text, "CSV_StartingStats", gd_key)
                if has_csv_stats
                else parse_scalar(text, gd_key)
            )
            # .tres 中未配置的字段使用 StartingStats 默认值，保证 CSV/XLSX 始终有数据
            # 百分比字段在资源里是 0~1 小数，回写表格时换算回"省略百分号"的写法
            row[csv_key] = runtime_to_percent(
                csv_key, raw if raw != "" else default_value
            )
        rows.append(row)
    write_csv_rows(MONSTER_CSV, MONSTER_HEADERS, rows)
    return rows


def create_combat_skill_resource(row: dict[str, str]) -> str:
    """生成最小 CombatSkillData 资源；后续复杂 Effects 仍由 Inspector 或专门效果表扩展。"""
    return "\n".join(
        [
            '[gd_resource type="Resource" format=3]',
            "",
            f'[ext_resource type="Script" path="{COMBAT_SKILL_SCRIPT}" id="combat_script"]',
            "",
            "[resource]",
            'script = ExtResource("combat_script")',
            f"Element = {row.get('element') or '0'}",
            f"TargetingType = {row.get('targeting_type') or '1'}",
            f"CardId = {string_or_null(row.get('card_id', ''))}",
            f"CardName = {godot_string(row.get('card_name', ''))}",
            f"Description = {godot_string(row.get('description', ''))}",
            "",
        ]
    )


def create_skill_card_resource(row: dict[str, str], combat_path: str) -> str:
    """生成最小 SkillCardData 资源，并链接对应 CombatSkillData。"""
    lines = [
        '[gd_resource type="Resource" format=3]',
        "",
        f'[ext_resource type="Script" uid="{SKILL_CARD_SCRIPT_UID}" path="{SKILL_CARD_SCRIPT}" id="skill_card_script"]',
        f'[ext_resource type="Resource" path="{combat_path}" id="combat_skill"]',
    ]
    icon_path = (row.get("icon_path") or "").strip()
    if icon_path:
        lines.append(
            f'[ext_resource type="Texture2D" path="{icon_path}" id="icon_skillcard"]'
        )
    lines.extend(
        [
            "",
            "[resource]",
            'script = ExtResource("skill_card_script")',
            'Skill = ExtResource("combat_skill")',
            f"cost = {row.get('cost') or '10'}",
            f"CardTags = {godot_string_array(row.get('tags', ''))}",
            f"CardId = {string_or_null(row.get('card_id', ''))}",
            f"CardName = {godot_string(row.get('card_name', ''))}",
            f"Description = {godot_string(row.get('description', ''))}",
        ]
    )
    if icon_path:
        lines.append('CardIcon = ExtResource("icon_skillcard")')
    lines.append("")
    return "\n".join(lines)


def create_monster_resource(row: dict[str, str], skill_paths: list[str]) -> str:
    """生成最小 MonsterData 资源，包含 StartingStats 与 SkillSet。"""
    lines = [
        '[gd_resource type="Resource" format=3]',
        "",
        f'[ext_resource type="Script" path="{MONSTER_SCRIPT}" id="monster_script"]',
        f'[ext_resource type="Script" path="{STARTING_STATS_SCRIPT}" id="starting_stats_script"]',
        f'[ext_resource type="Script" path="{MONSTER_SKILL_ENTRY_SCRIPT}" id="monster_skill_entry_script"]',
        f'[ext_resource type="Script" path="{MONSTER_SKILL_SET_SCRIPT}" id="monster_skill_set_script"]',
    ]
    for index, skill_path in enumerate(skill_paths, start=1):
        lines.append(
            f'[ext_resource type="Resource" path="{skill_path}" id="csv_skill_{index}"]'
        )
    lines.extend(
        [
            "",
            '[sub_resource type="Resource" id="CSV_StartingStats"]',
            'script = ExtResource("starting_stats_script")',
        ]
    )
    for csv_key, gd_key, default_value in STAT_FIELDS:
        # 表格中的百分比字段是"省略百分号"的写法，写入资源前必须换算成 0~1 小数
        stat_literal = percent_to_runtime(
            csv_key, row.get(csv_key) or default_value
        )
        lines.append(f"{gd_key} = {stat_literal}")
    for index, _skill_path in enumerate(skill_paths, start=1):
        lines.extend(
            [
                "",
                f'[sub_resource type="Resource" id="CSV_MonsterSkillEntry_{index}"]',
                'script = ExtResource("monster_skill_entry_script")',
                f'Skill = ExtResource("csv_skill_{index}")',
                "VisibleInPreview = true",
            ]
        )
    entry_refs = ", ".join(
        [
            f'SubResource("CSV_MonsterSkillEntry_{index}")'
            for index in range(1, len(skill_paths) + 1)
        ]
    )
    lines.extend(
        [
            "",
            '[sub_resource type="Resource" id="CSV_MonsterSkillSet"]',
            'script = ExtResource("monster_skill_set_script")',
            f'Skills = Array[Resource]([{entry_refs}])',
            "",
            "[resource]",
            'script = ExtResource("monster_script")',
            f"MonsterName = {godot_string(row.get('monster_name', '未知怪物'))}",
            'InitialAttributes = SubResource("CSV_StartingStats")',
            f"ElementalProperty = {row.get('element') or '0'}",
            f"Faction = {row.get('faction') or '0'}",
            'SkillSet = SubResource("CSV_MonsterSkillSet")',
            "",
        ]
    )
    return "\n".join(lines)


def upsert_existing_skill_card(
    path: Path, row: dict[str, str], combat_path: str
) -> str:
    """生成已有 SkillCardData 的更新文本，保留复杂资源引用与已有子资源。"""
    text = path.read_text(encoding="utf-8")
    header, resource_block = get_resource_block(text)
    # 技能卡已由 GDScript 提供；导入旧文件时同步清理 C# 全局类型标头和根资源元数据。
    header = re.sub(r'\s+script_class="SkillCardData"', "", header, count=1)
    resource_block = re.sub(
        r'^metadata/_custom_type_script\s*=.*\n?',
        "",
        resource_block,
        flags=re.MULTILINE,
    )
    script_match = re.search(
        r'^script\s*=\s*ExtResource\("([^"]+)"\)',
        resource_block,
        flags=re.MULTILINE,
    )
    if script_match is None:
        raise CardTableSyncError(
            f"技能卡资源缺少根脚本引用，已拒绝修改：{path.relative_to(ROOT)}"
        )
    script_resource_id = script_match.group(1)
    text = header + resource_block
    script_line_pattern = (
        r'^\[ext_resource[^\]]*id="'
        + re.escape(script_resource_id)
        + r'"[^\]]*\]\n?'
    )
    script_line = (
        f'[ext_resource type="Script" uid="{SKILL_CARD_SCRIPT_UID}" '
        f'path="{SKILL_CARD_SCRIPT}" id="{script_resource_id}"]\n'
    )
    text, replacement_count = re.subn(
        script_line_pattern,
        script_line,
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if replacement_count != 1:
        raise CardTableSyncError(
            f"技能卡根脚本声明无法定位，已拒绝修改：{path.relative_to(ROOT)}"
        )
    text = replace_or_add_resource_property(
        text, "CardId", string_or_null(row.get("card_id", ""))
    )
    text = replace_or_add_resource_property(
        text, "CardName", godot_string(row.get("card_name", ""))
    )
    text = replace_or_add_resource_property(
        text, "Description", godot_string(row.get("description", ""))
    )
    text = replace_or_add_resource_property(text, "cost", row.get("cost") or "10")
    text = replace_or_add_resource_property(
        text, "CardTags", godot_string_array(row.get("tags", ""))
    )
    skill_match = re.search(
        r'^Skill\s*=\s*ExtResource\("([^"]+)"\)', text, flags=re.MULTILINE
    )
    if skill_match:
        resource_id = skill_match.group(1)
        text = ensure_ext_resource(text, "Resource", combat_path, resource_id)
    return text


def upsert_existing_combat_skill(path: Path, row: dict[str, str]) -> str:
    """生成已有 CombatSkillData 的更新文本，保留 Effects 子资源。"""
    text = path.read_text(encoding="utf-8")
    # 战斗技能已由 GDScript 提供；导入旧文件时同步清理 C# 全局类型标头。
    text = re.sub(r'\s+script_class="CombatSkillData"', "", text, count=1)
    text = replace_or_add_resource_property(text, "Element", row.get("element") or "0")
    text = replace_or_add_resource_property(
        text, "TargetingType", row.get("targeting_type") or "1"
    )
    text = replace_or_add_resource_property(
        text, "CardId", string_or_null(row.get("card_id", ""))
    )
    text = replace_or_add_resource_property(
        text, "CardName", godot_string(row.get("card_name", ""))
    )
    text = replace_or_add_resource_property(
        text, "Description", godot_string(row.get("description", ""))
    )
    return text


def plan_skill_updates(rows: list[dict[str, str]]) -> tuple[dict[Path, str], dict[str, str]]:
    """根据技能表生成待写入文本，但在预检完成前不触碰磁盘中的资源。"""
    updates: dict[Path, str] = {}
    for row in rows:
        skill_card_path = resolve_skill_card_path(row)
        if not skill_card_path:
            continue
        combat_path = resolve_combat_skill_path(row, skill_card_path)
        if not combat_path:
            continue
        skill_card_file = to_disk_path(skill_card_path)
        combat_file = to_disk_path(combat_path)
        if combat_file.exists():
            combat_content = upsert_existing_combat_skill(combat_file, row)
        else:
            combat_content = create_combat_skill_resource(row)
        if not combat_file.exists() or combat_content != combat_file.read_text(encoding="utf-8"):
            updates[combat_file] = combat_content
        if skill_card_file.exists():
            skill_card_content = upsert_existing_skill_card(skill_card_file, row, combat_path)
        else:
            skill_card_content = create_skill_card_resource(row, combat_path)
        if (
            not skill_card_file.exists()
            or skill_card_content != skill_card_file.read_text(encoding="utf-8")
        ):
            updates[skill_card_file] = skill_card_content
    return updates, build_future_skill_key_map(rows)


def update_monster_skillset(text: str, skill_paths: list[str]) -> str:
    """更新已有怪物的 SkillSet，保留怪物其它资源字段与战利品等配置。"""
    text = strip_csv_subresources(text)
    text = remove_ext_resource_by_id(text, "csv_skill_")
    for index, skill_path in enumerate(skill_paths, start=1):
        text = ensure_ext_resource(text, "Resource", skill_path, f"csv_skill_{index}")
    block_lines: list[str] = []
    for index, _skill_path in enumerate(skill_paths, start=1):
        block_lines.extend(
            [
                f'[sub_resource type="Resource" id="CSV_MonsterSkillEntry_{index}"]',
                'script = ExtResource("csv_entry_script")',
                f'Skill = ExtResource("csv_skill_{index}")',
                "VisibleInPreview = true",
                "",
            ]
        )
    entry_refs = ", ".join(
        [
            f'SubResource("CSV_MonsterSkillEntry_{index}")'
            for index in range(1, len(skill_paths) + 1)
        ]
    )
    block_lines.extend(
        [
            '[sub_resource type="Resource" id="CSV_MonsterSkillSet"]',
            'script = ExtResource("csv_set_script")',
            f'Skills = Array[Resource]([{entry_refs}])',
            "",
        ]
    )
    text = ensure_ext_resource(
        text, "Script", MONSTER_SKILL_ENTRY_SCRIPT, "csv_entry_script"
    )
    text = ensure_ext_resource(
        text, "Script", MONSTER_SKILL_SET_SCRIPT, "csv_set_script"
    )
    insert_at = text.find("[resource]")
    if insert_at < 0:
        text = text.rstrip() + "\n" + "\n".join(block_lines)
    else:
        text = text[:insert_at] + "\n".join(block_lines) + text[insert_at:]
    return replace_or_add_resource_property(
        text, "SkillSet", 'SubResource("CSV_MonsterSkillSet")'
    )


def update_monster_stats(text: str, row: dict[str, str]) -> str:
    """更新怪物 StartingStats；始终重新构建 CSV_StartingStats，保证新增字段正确写入子资源块内。"""
    # 移除旧的 CSV_StartingStats，避免旧字段残留或新增字段被追加到文件末尾
    text = re.sub(
        r'\n?\[sub_resource[^\]]*id="CSV_StartingStats"[^\]]*\][\s\S]*?(?=\n\[(?:sub_resource|resource|ext_resource)|\Z)',
        "",
        text,
    )
    text = ensure_ext_resource(
        text, "Script", STARTING_STATS_SCRIPT, "csv_stats_script"
    )
    stats_lines = [
        '[sub_resource type="Resource" id="CSV_StartingStats"]',
        'script = ExtResource("csv_stats_script")',
    ]
    for csv_key, gd_key, default_value in STAT_FIELDS:
        csv_val = row.get(csv_key, "")
        # 表格中的百分比字段是"省略百分号"的写法，写入资源前必须换算成 0~1 小数
        stat_literal = percent_to_runtime(
            csv_key, csv_val if csv_val != "" else default_value
        )
        stats_lines.append(f"{gd_key} = {stat_literal}")
    insert_at = text.find("[resource]")
    if insert_at >= 0:
        text = text[:insert_at] + "\n".join(stats_lines) + "\n\n" + text[insert_at:]
    else:
        text = text.rstrip() + "\n" + "\n".join(stats_lines) + "\n"
    return replace_or_add_resource_property(
        text, "InitialAttributes", 'SubResource("CSV_StartingStats")'
    )


def plan_monster_updates(
    monster_rows: list[dict[str, str]],
    skill_rows: list[dict[str, str]],
    skill_key_map: dict[str, str],
) -> dict[Path, str]:
    """生成怪物资源更新，并合并技能表 monster_owners 的反向分配。"""
    updates: dict[Path, str] = {}
    monster_key_map = build_monster_key_map(monster_rows)
    owner_assignments: dict[str, list[str]] = {}
    managed_skill_paths: set[str] = set()
    skill_name_overrides: set[str] = set()
    for row in monster_rows:
        monster_path = resolve_monster_path(row)
        if monster_path and skill_names_were_edited(
            monster_path, row.get("skill_names", "")
        ):
            skill_name_overrides.add(monster_path)
    for row in skill_rows:
        combat_path = resolve_combat_skill_path(row, resolve_skill_card_path(row))
        if combat_path:
            managed_skill_paths.add(combat_path)
        for owner in split_semicolon_values(row.get("monster_owners") or ""):
            monster_path = monster_key_map.get(owner, owner)
            owner_assignments.setdefault(monster_path, [])
            if combat_path and combat_path not in owner_assignments[monster_path]:
                owner_assignments[monster_path].append(combat_path)
    for row in monster_rows:
        monster_path = resolve_monster_path(row)
        if not monster_path:
            continue
        skill_names_text = row.get("skill_names", "")
        skill_source_text = (
            skill_names_text if skill_names_text.strip() else row.get("skill_paths", "")
        )
        skill_paths = resolve_skill_paths(skill_source_text, skill_key_map)
        if monster_path not in skill_name_overrides:
            # 技能表 monster_owners 是技能归属的权威来源：先移除所有表格管理的技能，再按 owner 列重新追加。
            skill_paths = [
                path for path in skill_paths if path not in managed_skill_paths
            ]
        for assigned_path in owner_assignments.get(monster_path, []):
            if monster_path in skill_name_overrides:
                break
            if assigned_path not in skill_paths:
                skill_paths.append(assigned_path)
        monster_file = to_disk_path(monster_path)
        if not monster_file.exists():
            updates[monster_file] = create_monster_resource(row, skill_paths)
            continue
        text = monster_file.read_text(encoding="utf-8")
        text = replace_or_add_resource_property(
            text, "MonsterName", godot_string(row.get("monster_name", "未知怪物"))
        )
        text = replace_or_add_resource_property(
            text, "ElementalProperty", row.get("element") or "0"
        )
        text = replace_or_add_resource_property(
            text, "Faction", row.get("faction") or "0"
        )
        # skillset 的 strip_csv_subresources 会清除所有 CSV_* 子资源，因此必须先调用 skillset 再调用 stats，
        # 避免 stats 刚创建的 CSV_StartingStats 被 skillset 误删
        text = update_monster_skillset(text, skill_paths)
        text = update_monster_stats(text, row)
        if text != monster_file.read_text(encoding="utf-8"):
            updates[monster_file] = text
    return updates


def export_all() -> SyncResult:
    """从资源安全导出两张 CSV 与 XLSX 工作簿，并返回真实写入目标。"""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    owners, monster_skills, monster_names = collect_monster_skill_map()
    skill_rows = export_skill_csv(owners, monster_names)
    monster_rows = export_monster_csv(monster_skills)
    xlsx_target = write_xlsx_workbook(skill_rows, monster_rows)
    write_sync_state()
    print(f"已导出：{SKILL_CSV.relative_to(ROOT)}")
    print(f"已导出：{MONSTER_CSV.relative_to(ROOT)}")
    print(f"已导出：{xlsx_target.relative_to(ROOT)}")
    warnings = (
        [f"主 XLSX 正被占用，已写入待应用文件：{xlsx_target.relative_to(ROOT)}"]
        if xlsx_target == PENDING_XLSX_FILE
        else []
    )
    return SyncResult("已导出卡牌表格", [SKILL_CSV, MONSTER_CSV, xlsx_target], warnings)


def import_all() -> SyncResult:
    """预检两张表后批量原子回写 `.tres` 资源，失败时不进入写入阶段。"""
    (
        skill_headers,
        skill_rows_raw,
        monster_headers,
        monster_rows_raw,
        source_name,
    ) = read_card_tables()
    print(
        f"正在预检 {source_name}：技能行 {len(skill_rows_raw)} 条，怪物行 {len(monster_rows_raw)} 条。"
    )
    skill_rows, monster_rows = validate_import_rows(
        skill_headers, skill_rows_raw, monster_headers, monster_rows_raw
    )
    skill_updates, skill_key_map = plan_skill_updates(skill_rows)
    monster_updates = plan_monster_updates(monster_rows, skill_rows, skill_key_map)
    duplicated_paths = set(skill_updates).intersection(monster_updates)
    if duplicated_paths:
        duplicated_text = ", ".join(str(path.relative_to(ROOT)) for path in duplicated_paths)
        raise CardTableSyncError(f"待写入资源路径重复，已拒绝同步：{duplicated_text}")
    updates = {**skill_updates, **monster_updates}
    changed_files, backup_root = write_resource_batch_atomically(updates)
    if backup_root is not None:
        print(f"已创建同步备份：{backup_root.relative_to(ROOT)}")
    if changed_files:
        print(f"已原子更新 {len(changed_files)} 个 Godot 资源。")
    else:
        print("表格校验通过，资源内容无需更新。")
    write_sync_state()
    return SyncResult("已导入卡牌表格", changed_files)


def auto_sync() -> SyncResult:
    """推荐同步入口：按变更方向安全导入或导出，未变化时明确返回空结果。"""
    promoted_pending = promote_pending_xlsx()
    latest_resource_time = get_latest_resource_time()
    latest_csv_time = max(get_csv_signature().values())
    if csv_changed_since_last_sync():
        import_result = import_all()
        export_result = export_all()
        return SyncResult(
            "已安全同步卡牌表格",
            import_result.changed_files + export_result.changed_files,
            import_result.warnings + export_result.warnings,
        )
    elif latest_resource_time > latest_csv_time:
        return export_all()
    else:
        write_sync_state()
        changed_files = [XLSX_FILE] if promoted_pending else []
        return SyncResult("无需同步，表格与资源已是最新状态", changed_files)


def ensure_workbook() -> SyncResult:
    """仅在 XLSX 缺失时补建工作簿，优先保留用户已维护的 CSV 内容。"""
    if XLSX_FILE.exists():
        return SyncResult("卡牌表格已存在，无需重新生成")
    if SKILL_CSV.exists() and MONSTER_CSV.exists():
        skill_rows = read_csv_rows(SKILL_CSV)
        monster_rows = read_csv_rows(MONSTER_CSV)
        xlsx_target = write_xlsx_workbook(skill_rows, monster_rows)
        return SyncResult("已根据现有 CSV 创建卡牌表格", [xlsx_target])
    if SKILL_CSV.exists() or MONSTER_CSV.exists():
        raise CardTableSyncError("CSV 表格不完整，已拒绝生成可能遗漏数据的 XLSX 工作簿。")
    return export_all()


def print_result(
    result: SyncResult,
    success: bool,
    error: str = "",
    result_file: Path | None = None,
    request_id: str = "",
) -> bool:
    """以 UTF-8 结果文件和单行控制台摘要报告最终状态。

    参数:
        result: 本次操作的动作说明、改动文件和警告。
        success: 整次操作是否完整成功。
        error: 失败时展示给用户的错误原因。
        result_file: Godot 指定的结果文件；为空时仅输出控制台摘要。
        request_id: Godot 为本次调用生成的唯一标识，用于拒绝旧结果文件。
    返回:
        结果文件写入成功或未要求写入时返回 True；写入失败时返回 False。
    """
    # 同一份载荷同时用于结果文件和控制台，避免两个输出通道的状态发生分歧。
    payload = result.to_payload(success, error, request_id)
    # JSON 保留中文，文件与控制台均统一使用 UTF-8。
    payload_text = json.dumps(payload, ensure_ascii=False)
    if result_file is not None:
        try:
            # 结果文件明确使用 UTF-8，避免 Windows 控制台编码影响机器协议。
            write_text_atomically(result_file, payload_text, encoding="utf-8")
        except CardTableSyncError as write_error:
            # 写入机器结果失败本身属于整次操作失败，不能继续向 Godot 报告成功。
            result_file_error = f"写入同步结果文件失败：{write_error}"
            # 控制台仍输出带请求标识的失败摘要，作为结果文件不可用时的最后诊断通道。
            fallback_payload = SyncResult("同步失败").to_payload(
                False, result_file_error, request_id
            )
            print(
                RESULT_PREFIX
                + json.dumps(fallback_payload, ensure_ascii=False)
            )
            return False
    print(RESULT_PREFIX + payload_text)
    return True


def main() -> None:
    """命令行入口。"""
    parser = argparse.ArgumentParser(description="同步 CUSGA 技能卡与怪物卡 CSV。")
    parser.add_argument(
        "--import",
        dest="do_import",
        action="store_true",
        help="把 CSV 回写到 .tres 资源。",
    )
    parser.add_argument(
        "--export",
        dest="do_export",
        action="store_true",
        help="从 .tres 资源导出 CSV。",
    )
    parser.add_argument(
        "--sync", dest="do_sync", action="store_true", help="先导入再导出。"
    )
    parser.add_argument(
        "--auto",
        dest="do_auto",
        action="store_true",
        help="按修改时间自动判断导入或导出。",
    )
    parser.add_argument(
        "--ensure-workbook",
        dest="ensure_workbook",
        action="store_true",
        help="仅在 XLSX 缺失时创建工作簿，优先保留现有 CSV。",
    )
    parser.add_argument(
        "--result-file",
        dest="result_file",
        default="",
        help="把最终 JSON 以 UTF-8 写入指定文件，供 Godot 编辑器可靠读取。",
    )
    parser.add_argument(
        "--request-id",
        dest="request_id",
        default="",
        help="写入最终 JSON 的本次调用标识，避免读取旧结果。",
    )
    args = parser.parse_args()
    do_auto = cast(bool, args.do_auto)
    do_sync = cast(bool, args.do_sync)
    do_import = cast(bool, args.do_import)
    do_ensure_workbook = cast(bool, args.ensure_workbook)
    # 空路径表示手工命令行模式，保持只输出控制台摘要的兼容行为。
    result_file_text = cast(str, args.result_file).strip()
    # Godot 传入绝对路径，解析后交给原子写入函数保存 UTF-8 JSON。
    result_file = Path(result_file_text).resolve() if result_file_text else None
    # 请求标识原样回传，调用方据此拒绝旧结果文件。
    request_id = cast(str, args.request_id).strip()
    try:
        if do_ensure_workbook:
            result = ensure_workbook()
        elif do_auto:
            result = auto_sync()
        elif do_sync:
            import_result = import_all()
            export_result = export_all()
            result = SyncResult(
                "已同步卡牌表格",
                import_result.changed_files + export_result.changed_files,
                import_result.warnings + export_result.warnings,
            )
        elif do_import:
            result = import_all()
        else:
            result = export_all()
    except CardTableSyncError as error:
        message = str(error)
        print(f"[错误] {message}")
        print_result(
            SyncResult("同步失败"), False, message, result_file, request_id
        )
        raise SystemExit(1) from error
    except Exception as error:
        message = f"发生未预期异常：{error}"
        print(f"[错误] {message}")
        print_result(
            SyncResult("同步失败"), False, message, result_file, request_id
        )
        raise SystemExit(1) from error
    if not print_result(result, True, "", result_file, request_id):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
