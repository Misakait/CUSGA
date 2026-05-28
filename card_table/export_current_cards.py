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
import html
import json
import re
import zipfile
from pathlib import Path
from typing import cast
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

SKILL_CARD_SCRIPT = "res://resources/item/card/SkillCardData.cs"
COMBAT_SKILL_SCRIPT = "res://core/combat/skills/CombatSkillData.cs"
MONSTER_SCRIPT = "res://resources/monster/MonsterData.cs"
STARTING_STATS_SCRIPT = "res://resources/stats/StartingStats.cs"
MONSTER_SKILL_ENTRY_SCRIPT = "res://resources/monster/MonsterSkillEntryData.cs"
MONSTER_SKILL_SET_SCRIPT = "res://resources/monster/MonsterSkillSetData.cs"

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

MONSTER_HEADERS = [
    "resource_path",
    "id_slug",
    "monster_name",
    "element",
    "faction",
    "max_health",
    "model_scene_path",
    "behavior_tree_scene_path",
    "skill_names",
    "base_phys_atk",
    "base_phys_def",
    "base_mag_power",
    "base_mag_resist",
    "base_speed",
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
]


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
    STATE_FILE.write_text(
        json.dumps(get_csv_signature(), ensure_ascii=False, indent=2), encoding="utf-8"
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


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    """读取 CSV，兼容 UTF-8、UTF-8-BOM、GBK/GB18030。"""
    if not path.exists():
        return []
    import io

    content = read_text_with_csv_encoding(path)
    return [dict(row) for row in csv.DictReader(io.StringIO(content))]


def write_csv_rows(path: Path, headers: list[str], rows: list[dict[str, str]]) -> bool:
    """写入 UTF-8-BOM CSV；文件被 Excel/WPS 锁定时跳过导出但不阻断资源导入。"""
    try:
        with path.open("w", encoding="utf-8-sig", newline="") as file:
            writer = csv.DictWriter(file, fieldnames=headers)
            writer.writeheader()
            writer.writerows(rows)
        return True
    except PermissionError:
        print(f"CSV 文件正在被外部程序占用，已跳过导出：{path}")
        return False


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
) -> bool:
    """导出带下拉框的 XLSX；CSV 继续作为自动同步底层格式，XLSX 负责更友好的人工编辑。"""
    try:
        promote_pending_xlsx()
        option_rows = build_options_rows()
        target_file = XLSX_FILE if xlsx_is_writable(XLSX_FILE) else PENDING_XLSX_FILE
        if target_file == PENDING_XLSX_FILE:
            print(
                f"XLSX 文件正在被外部程序占用，本次导出写入待应用文件：{PENDING_XLSX_FILE.relative_to(ROOT)}"
            )
        with zipfile.ZipFile(target_file, "w", zipfile.ZIP_DEFLATED) as archive:
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
        return target_file == XLSX_FILE
    except PermissionError:
        print(f"XLSX 文件正在被外部程序占用，已跳过导出：{XLSX_FILE}")
        return False


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


def read_xlsx_sheet(sheet_path: str) -> list[dict[str, str]]:
    """读取本工具生成的 XLSX 工作表，供使用下拉框编辑后的文件重新导入。"""
    if not XLSX_FILE.exists():
        return []
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
        return []
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
    return result


def read_card_tables() -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    """优先读取被用户改过的 XLSX；没有改动工作簿时回退到 CSV。"""
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
        return (
            read_xlsx_sheet("xl/worksheets/sheet1.xml"),
            read_xlsx_sheet("xl/worksheets/sheet2.xml"),
        )
    print("正在读取 CSV 表格。")
    return read_csv_rows(SKILL_CSV), read_csv_rows(MONSTER_CSV)


def parse_resource_paths(text: str) -> dict[str, str]:
    """解析 `.tres` 中 ExtResource id 到资源路径的映射。"""
    resources: dict[str, str] = {}
    for match in re.finditer(
        r'\[ext_resource[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"', text
    ):
        resources[match.group(2)] = match.group(1)
    return resources


def parse_scalar(text: str, key: str, default: str = "") -> str:
    """读取 `.tres` 资源段里的简单标量字段。"""
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


def parse_ext_assignment(text: str, key: str, resources: dict[str, str]) -> str:
    """读取 `Skill = ExtResource("...")` 这类资源引用字段。"""
    match = re.search(
        rf"^{re.escape(key)}\s*=\s*ExtResource\(\"([^\"]+)\"\)",
        text,
        flags=re.MULTILINE,
    )
    if not match:
        return ""
    return resources.get(match.group(1), "")


def parse_array_strings(text: str, key: str) -> str:
    """读取 `Array[String](["a", "b"])` 并用分号输出，适配 CSV 中的多值字段。"""
    match = re.search(
        rf"^{re.escape(key)}\s*=\s*Array\[String\]\(\[(.*)\]\)",
        text,
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
    if re.search(pattern, text, flags=re.MULTILINE):
        return re.sub(pattern, replacement, text, count=1, flags=re.MULTILINE)
    return text.rstrip() + "\n" + replacement + "\n"


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
        rows.append(
            {
                "resource_path": res_path,
                "id_slug": derive_id_slug_from_path(res_path, path.stem),
                "monster_name": parse_scalar(text, "MonsterName"),
                "element": element_to_label(parse_scalar(text, "ElementalProperty")),
                "faction": parse_scalar(text, "Faction", "0"),
                "max_health": parse_scalar(text, "MaxHealth"),
                "model_scene_path": parse_ext_assignment(text, "ModelScene", resources),
                "behavior_tree_scene_path": parse_ext_assignment(
                    text, "BehaviorTreeScene", resources
                ),
                "skill_names": ";".join(skill_names),
                "base_phys_atk": parse_scalar(text, "BasePhysAtk"),
                "base_phys_def": parse_scalar(text, "BasePhysDef"),
                "base_mag_power": parse_scalar(text, "BaseMagPower"),
                "base_mag_resist": parse_scalar(text, "BaseMagResist"),
                "base_speed": parse_scalar(text, "BaseSpeed"),
            }
        )
    write_csv_rows(MONSTER_CSV, MONSTER_HEADERS, rows)
    return rows


def create_combat_skill_resource(row: dict[str, str]) -> str:
    """生成最小 CombatSkillData 资源；后续复杂 Effects 仍由 Inspector 或专门效果表扩展。"""
    return "\n".join(
        [
            '[gd_resource type="Resource" script_class="CombatSkillData" format=3]',
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
        '[gd_resource type="Resource" script_class="SkillCardData" format=3]',
        "",
        f'[ext_resource type="Script" path="{SKILL_CARD_SCRIPT}" id="skill_card_script"]',
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
        '[gd_resource type="Resource" script_class="MonsterData" format=3]',
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
        lines.append(f"{gd_key} = {row.get(csv_key) or default_value}")
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
            f'Skills = Array[ExtResource("monster_skill_entry_script")]([{entry_refs}])',
            "",
            "[resource]",
            'script = ExtResource("monster_script")',
            f"MonsterName = {godot_string(row.get('monster_name', '未知怪物'))}",
            'InitialAttributes = SubResource("CSV_StartingStats")',
            f"ElementalProperty = {row.get('element') or '0'}",
            f"Faction = {row.get('faction') or '0'}",
            f"MaxHealth = {row.get('max_health') or '100'}",
            'SkillSet = SubResource("CSV_MonsterSkillSet")',
            "",
        ]
    )
    return "\n".join(lines)


def upsert_existing_skill_card(
    path: Path, row: dict[str, str], combat_path: str
) -> None:
    """更新已有 SkillCardData 的基础字段，保留复杂资源引用与已有子资源。"""
    text = path.read_text(encoding="utf-8")
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
    path.write_text(text, encoding="utf-8")


def upsert_existing_combat_skill(path: Path, row: dict[str, str]) -> None:
    """更新已有 CombatSkillData 的基础字段，保留 Effects 子资源。"""
    text = path.read_text(encoding="utf-8")
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
    path.write_text(text, encoding="utf-8")


def apply_skill_rows(rows: list[dict[str, str]]) -> dict[str, str]:
    """导入技能卡表，返回技能索引供怪物技能分配使用。"""
    for row in rows:
        skill_card_path = resolve_skill_card_path(row)
        if not skill_card_path:
            continue
        combat_path = resolve_combat_skill_path(row, skill_card_path)
        if not combat_path:
            continue
        skill_card_file = to_disk_path(skill_card_path)
        combat_file = to_disk_path(combat_path)
        skill_card_file.parent.mkdir(parents=True, exist_ok=True)
        combat_file.parent.mkdir(parents=True, exist_ok=True)
        if combat_file.exists():
            upsert_existing_combat_skill(combat_file, row)
        else:
            combat_file.write_text(create_combat_skill_resource(row), encoding="utf-8")
        if skill_card_file.exists():
            upsert_existing_skill_card(skill_card_file, row, combat_path)
        else:
            skill_card_file.write_text(
                create_skill_card_resource(row, combat_path), encoding="utf-8"
            )
    return build_skill_key_map()


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
            f'Skills = Array[ExtResource("csv_entry_script")]([{entry_refs}])',
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
    """更新怪物 StartingStats；没有属性资源时追加 CSV 专用属性子资源。"""
    has_stats = bool(
        re.search(r"^InitialAttributes\s*=\s*SubResource\(", text, flags=re.MULTILINE)
    )
    if not has_stats:
        text = ensure_ext_resource(
            text, "Script", STARTING_STATS_SCRIPT, "csv_stats_script"
        )
        stats_lines = [
            '[sub_resource type="Resource" id="CSV_StartingStats"]',
            'script = ExtResource("csv_stats_script")',
        ]
        for csv_key, gd_key, default_value in STAT_FIELDS:
            stats_lines.append(f"{gd_key} = {row.get(csv_key) or default_value}")
        insert_at = text.find("[resource]")
        if insert_at >= 0:
            text = text[:insert_at] + "\n".join(stats_lines) + "\n\n" + text[insert_at:]
        else:
            text = text.rstrip() + "\n" + "\n".join(stats_lines) + "\n"
        return replace_or_add_resource_property(
            text, "InitialAttributes", 'SubResource("CSV_StartingStats")'
        )
    for csv_key, gd_key, _default_value in STAT_FIELDS:
        if row.get(csv_key, "") != "":
            text = replace_or_add_line(text, gd_key, row[csv_key])
    return text


def apply_monster_rows(
    monster_rows: list[dict[str, str]],
    skill_rows: list[dict[str, str]],
    skill_key_map: dict[str, str],
) -> None:
    """导入怪物表，并合并技能表 monster_owners 反向分配。"""
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
        monster_file.parent.mkdir(parents=True, exist_ok=True)
        if not monster_file.exists():
            monster_file.write_text(
                create_monster_resource(row, skill_paths), encoding="utf-8"
            )
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
        text = replace_or_add_resource_property(
            text, "MaxHealth", row.get("max_health") or "100"
        )
        text = update_monster_stats(text, row)
        text = update_monster_skillset(text, skill_paths)
        monster_file.write_text(text, encoding="utf-8")


def export_all() -> None:
    """从资源导出两张 CSV。"""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    owners, monster_skills, monster_names = collect_monster_skill_map()
    skill_rows = export_skill_csv(owners, monster_names)
    monster_rows = export_monster_csv(monster_skills)
    write_xlsx_workbook(skill_rows, monster_rows)
    write_sync_state()
    print(f"已导出：{SKILL_CSV.relative_to(ROOT)}")
    print(f"已导出：{MONSTER_CSV.relative_to(ROOT)}")
    print(f"已导出：{XLSX_FILE.relative_to(ROOT)}")


def import_all() -> None:
    """从两张 CSV 回写 `.tres` 资源。"""
    skill_rows_raw, monster_rows_raw = read_card_tables()
    print(f"读取到技能行 {len(skill_rows_raw)} 条，怪物行 {len(monster_rows_raw)} 条。")
    skill_rows = [normalize_skill_row_for_import(row) for row in skill_rows_raw]
    monster_rows = [normalize_monster_row_for_import(row) for row in monster_rows_raw]
    skill_key_map = apply_skill_rows(skill_rows)
    apply_monster_rows(monster_rows, skill_rows, skill_key_map)
    print("已导入 CSV 到 Godot 资源。")


def auto_sync() -> None:
    """自动同步入口：CSV/XLSX 外部修改时先导入再导出，否则仅在资源较新时导出。"""
    promote_pending_xlsx()
    latest_resource_time = get_latest_resource_time()
    latest_csv_time = max(get_csv_signature().values())
    if csv_changed_since_last_sync():
        import_all()
        export_all()
    elif latest_resource_time > latest_csv_time:
        export_all()
    else:
        write_sync_state()


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
    args = parser.parse_args()
    do_auto = cast(bool, args.do_auto)
    do_sync = cast(bool, args.do_sync)
    do_import = cast(bool, args.do_import)
    if do_auto:
        auto_sync()
    elif do_sync:
        import_all()
        export_all()
    elif do_import:
        import_all()
        write_sync_state()
    else:
        export_all()


if __name__ == "__main__":
    main()
