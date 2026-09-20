@tool
extends McpTestSuite

## StartingStats 迁移契约套件（C# 垫片 ↔ GDScript 生产实现）。
##
## 背景：怪物资产的 InitialAttributes 早已指向 res://resources/stats/starting_stats.gd，
## 但遭遇缩放的属性副本原先仍写 `StartingStats.new()`，在标识符层面解析到旧 C# 全局类。
## 本批把生产构造切到 GDScript 实现，并用本套件锁死：
## 1）两侧 30 个字段名、顺序与默认值完全一致；
## 2）旧 C# StartingStats.cs 继续作为兼容垫片（GlobalClass + 30 个 [Export] 字段）保留；
## 3）生产 GDScript 对旧 C# 全局类 StartingStats 零引用；
## 4）运行时缩放结果与怪物缩放端到端结果都是 GDScript 资源。
##
## C# 物理退役后，依赖垫片的对照断言经 CS_OPTIONAL 自动退场（见 tests/godot/csharp_optional.gd）。

const STARTING_STATS_CS: String = "res://resources/stats/StartingStats.cs"
const STARTING_STATS_GD: String = "res://resources/stats/starting_stats.gd"
const MONSTER_DATA_CS: String = "res://resources/monster/MonsterData.cs"
const MONSTER_DATA_GD: String = "res://resources/monster/monster_data.gd"
const ENCOUNTER_MANAGER_GD: String = "res://core/application/encounter_manager.gd"
const MONSTER_GD: String = "res://entities/monster.gd"
const MONSTER_DIR: String = "res://resources/monster"
const KU_MONSTER: String = "res://resources/monster/tree_kumujing.tres"

## 迁移期 C# 可选助手：C# 退役后 C# 对照断言自动退场，GDScript 侧断言照跑。
## 说明见 tests/godot/csharp_optional.gd。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## 生产根目录（不含 tests：测试文件允许引用旧路径作为对照）。
const PRODUCTION_ROOTS: Array = [
	"res://core", "res://entities", "res://resources", "res://scripts", "res://scenes",
]

## 缺省倍率协议（六个字段全为 1）。
const TERRAIN_ONE: Dictionary = {
	"MaxHealth": 1.0, "PhysAtk": 1.0, "PhysDef": 1.0,
	"MagPower": 1.0, "MagResist": 1.0, "Speed": 1.0,
}


func suite_name() -> String:
	return "starting_stats_contract"


# ----- 解析与扫描助手 -----

## 读取文本文件内容。
##
## 参数 path：res:// 路径。
## 返回值：文件正文；读取失败时返回空字符串。
func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## 去掉 GDScript 的注释，保留字符串字面量与换行。
##
## 参数 text：GDScript 源码。
## 返回值：注释被移除的源码。
func _strip_gd_comments(text: String) -> String:
	var out: String = ""
	var in_string: bool = false
	var index: int = 0
	var length: int = text.length()
	while index < length:
		var character: String = text[index]
		if in_string:
			out += character
			if character == "\\" and index + 1 < length:
				out += text[index + 1]
				index += 2
				continue
			if character == "\"":
				in_string = false
			index += 1
			continue
		if character == "\"":
			in_string = true
			out += character
			index += 1
			continue
		if character == "#":
			while index < length and text[index] != "\n":
				index += 1
			continue
		out += character
		index += 1
	return out


## 解析 C# `[Export] public float NAME { get; set; } = VALUEF;` 的字段顺序与默认值。
##
## 参数 text：C# 源码。
## 返回值：按源码顺序插入的字段名到默认值字典。
func _csharp_export_defaults(text: String) -> Dictionary:
	var out: Dictionary = {}
	var marker: String = "[Export] public float "
	for line: String in text.split("\n"):
		var index: int = line.find(marker)
		if index == -1:
			continue
		var rest: String = line.substr(index + marker.length())
		var name_end: int = rest.find(" ")
		if name_end == -1:
			continue
		var field: String = rest.substr(0, name_end)
		var equals_index: int = rest.rfind("=")
		if equals_index == -1:
			continue
		var value_text: String = rest.substr(equals_index + 1).strip_edges().trim_suffix(";")
		out[field] = float(value_text.strip_edges().trim_suffix("f"))
	return out


## 解析 GDScript `@export var NAME: float = VALUE` 的字段顺序与默认值。
##
## 参数 text：GDScript 源码。
## 返回值：按源码顺序插入的字段名到默认值字典。
func _gd_export_defaults(text: String) -> Dictionary:
	var out: Dictionary = {}
	for line: String in _strip_gd_comments(text).split("\n"):
		var trimmed: String = line.strip_edges()
		if not trimmed.begins_with("@export var "):
			continue
		var rest: String = trimmed.substr("@export var ".length())
		var name_end: int = rest.find(":")
		if name_end == -1:
			continue
		var field: String = rest.substr(0, name_end)
		var value: float = 0.0
		var equals_index: int = rest.find("=")
		if equals_index != -1:
			value = float(rest.substr(equals_index + 1).strip_edges())
		out[field] = value
	return out


## 递归扫描指定扩展名的文件里是否出现目标文本。
##
## 参数 directory：起始目录。
## 参数 needle：目标文本；传空字符串表示「列出全部匹配扩展名的文件」。
## 注意：Godot 的 String.find("") 返回 -1（不是 0），因此「匹配全部」必须显式判定 needle == ""。
## 参数 extensions：扩展名白名单（不含点）。
## 参数 code_only：为真时先去掉 GDScript 注释再匹配。
## 返回值：命中的文件路径数组。
func _scan(directory: String, needle: String, extensions: Array, code_only: bool = false) -> Array:
	var hits: Array = []
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return hits
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = directory.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with(".") and entry != "addons" and entry != "obj":
				hits.append_array(_scan(full, needle, extensions, code_only))
		elif extensions.has(entry.get_extension()):
			var text: String = FileAccess.get_file_as_string(full)
			if code_only:
				text = _strip_gd_comments(text)
			if needle == "" or text.find(needle) != -1:
				hits.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return hits


## 按「完整标识符」递归扫描 GDScript 生产代码。
##
## 参数 directory：起始目录。
## 参数 identifier：目标标识符。
## 返回值：命中的文件路径数组。
##
## 用词边界而不是子串：生产脚本里的 `PlayerStartingStats` 字段名包含 `StartingStats`，
## 直接 contains 会造成假失败；这里要求标识符前后都不是字母、数字或下划线。
func _scan_identifier(directory: String, identifier: String, extensions: Array) -> Array:
	var hits: Array = []
	var regex: RegEx = RegEx.create_from_string("(?<![A-Za-z0-9_])" + identifier + "(?![A-Za-z0-9_])")
	if regex == null:
		return hits
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return hits
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = directory.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with(".") and entry != "addons" and entry != "obj":
				hits.append_array(_scan_identifier(full, identifier, extensions))
		elif extensions.has(entry.get_extension()):
			var text: String = _strip_gd_comments(FileAccess.get_file_as_string(full))
			if regex.search(text) != null:
				hits.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return hits


# ----- 字段与默认值 -----

## 两侧 30 个字段的名称、顺序与默认值必须逐条一致。
func test_field_and_default_parity() -> void:
	var cs_defaults: Dictionary = _csharp_export_defaults(_read(STARTING_STATS_CS))
	var gd_defaults: Dictionary = _gd_export_defaults(_read(STARTING_STATS_GD))
	assert_eq(gd_defaults.size(), 30, "starting_stats.gd 必须保留 30 个字段。")
	# C# 对照部分：垫片退役后整段退场，GDScript 侧断言仍照跑。
	if cs_defaults.is_empty():
		return
	assert_eq(cs_defaults.size(), 30, "旧 C# StartingStats 必须保留 30 个字段。")
	assert_eq(gd_defaults.keys(), cs_defaults.keys(), "两侧字段名与顺序必须逐字一致。")
	for field: String in cs_defaults.keys():
		assert_eq(
			float(gd_defaults.get(field, -1.0)),
			float(cs_defaults[field]),
			"字段 %s 的默认值必须与旧 C# 相同。" % field
		)


## 旧 C# 垫片的可序列化表面必须完整保留。
func test_csharp_shim_keeps_global_class_surface() -> void:
	var cs: String = _read(STARTING_STATS_CS)
	if cs.is_empty():
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	assert_true(cs.contains("[GlobalClass]"), "旧 C# StartingStats 必须仍标记 GlobalClass。")
	assert_true(
		cs.contains("public partial class StartingStats : Resource"),
		"旧 C# StartingStats 必须仍继承 Resource。"
	)
	assert_true(ResourceLoader.exists(STARTING_STATS_CS), "旧 C# 垫片必须保留到全量迁移完成。")
	assert_true(
		cs.contains("MaxHealthGrowth { get; set; } = 0f;"),
		"旧 C# 垫片字段不得被改写。"
	)
	assert_true(
		_read(MONSTER_DATA_CS).contains("= new StartingStats()"),
		"旧 C# MonsterData 的默认 InitialAttributes 必须保留。"
	)


# ----- 生产依赖边界 -----

## 生产 GDScript 不得再引用旧 C# 全局类 StartingStats。
func test_production_gdscript_has_no_csharp_starting_stats_reference() -> void:
	var hits: Array = []
	for root: String in PRODUCTION_ROOTS:
		hits.append_array(_scan_identifier(root, "StartingStats", ["gd"]))
	assert_eq(hits, [], "生产 GDScript 不得再引用旧 C# 全局类 StartingStats：%s" % str(hits))
	var manager: String = _strip_gd_comments(_read(ENCOUNTER_MANAGER_GD))
	assert_true(
		manager.contains(
			"const STARTING_STATS_SCRIPT: GDScript = preload(\"res://resources/stats/starting_stats.gd\")"
		),
		"遭遇管理必须显式 preload GDScript StartingStats。"
	)
	assert_true(
		manager.contains("var scaled: Resource = STARTING_STATS_SCRIPT.new()"),
		"遭遇缩放的属性副本必须构造 GDScript StartingStats。"
	)
	var monster: String = _strip_gd_comments(_read(MONSTER_GD))
	assert_true(
		monster.contains(
			"const STARTING_STATS_SCRIPT: GDScript = preload(\"res://resources/stats/starting_stats.gd\")"
		),
		"怪物兜底属性资源必须使用同一 GDScript 实现。"
	)


# ----- 运行时行为 -----

## 缩放结果必须是 GDScript 资源，且数值遵循旧 C# 公式。
func test_scaled_stats_resource_is_gdscript_implementation() -> void:
	var manager: Node = track((load(ENCOUNTER_MANAGER_GD) as GDScript).new())
	assert_true(manager != null, "遭遇管理脚本必须可实例化。")
	var source: Resource = (load(STARTING_STATS_GD) as GDScript).new()
	source.set("BasePhysAtk", 80.0)
	source.set("MaxHealthGrowth", 7.0)
	var terrain: Dictionary = TERRAIN_ONE.duplicate()
	terrain["MaxHealth"] = 2.0
	terrain["PhysAtk"] = 1.5
	var day: Dictionary = TERRAIN_ONE.duplicate()
	day["MaxHealth"] = 1.3
	var scaled: Resource = manager.call("_scale_stats", source, terrain, day)
	assert_true(scaled != null, "缩放必须返回属性资源。")
	var scaled_script: Script = scaled.get_script() as Script
	assert_true(scaled_script != null, "缩放结果必须带脚本。")
	assert_eq(scaled_script.resource_path, STARTING_STATS_GD, "缩放结果必须是 GDScript StartingStats 实例。")
	assert_eq(float(scaled.get("BasePhysAtk")), 120.0, "BasePhysAtk 必须按 80 * 1.5 * 1.0 缩放。")
	assert_eq(float(scaled.get("BaseMaxHealth")), 2600.0, "缺省 BaseMaxHealth 必须按 1000 * 2.0 * 1.3 缩放。")
	assert_eq(float(scaled.get("MaxHealthGrowth")), 7.0, "成长字段必须原样复制、不参与缩放。")
	assert_true(scaled != source, "缩放必须产出新资源，不得改写入参。")
	var defaults: Dictionary = _gd_export_defaults(_read(STARTING_STATS_GD))
	for field: String in defaults.keys():
		assert_true(scaled.get(field) != null, "缩放结果必须保留字段 %s。" % field)
	var manager_code: String = _strip_gd_comments(_read(ENCOUNTER_MANAGER_GD))
	assert_true(
		manager_code.find("StartingStats.new()") == -1,
		"生产缩放不得再实例化旧 C# StartingStats。"
	)


## 怪物资产必须已经指向 GDScript StartingStats。
func test_monster_assets_use_gdscript_starting_stats() -> void:
	var files: Array = _scan(MONSTER_DIR, "", ["tres"])
	assert_true(
		files.size() > 40,
		"怪物资源目录必须仍然存在，资产不得丢失：files=%d" % files.size()
	)
	var stats_assets: int = 0
	for path: String in files:
		var text: String = FileAccess.get_file_as_string(path)
		assert_false(text.contains("StartingStats.cs"), "%s 不得引用旧 C# StartingStats.cs。" % path)
		if text.find("CSV_StartingStats") == -1 and text.find("Resource_stats") == -1:
			continue
		stats_assets += 1
		assert_true(
			text.contains("path=\"res://resources/stats/starting_stats.gd\""),
			"%s 的初始属性子资源必须指向 GDScript StartingStats。" % path
		)
	assert_gt(stats_assets, 40, "至少 40 个怪物资产必须携带初始属性子资源。")


## 端到端：缩放后的怪物与初始属性都必须是 GDScript 资源，且外观字段原样保留。
func test_scale_monsters_end_to_end_keeps_gdscript_resources() -> void:
	var monster: Resource = load(KU_MONSTER)
	assert_true(monster != null, "枯木精资产必须可加载。")
	var manager: Node = track((load(ENCOUNTER_MANAGER_GD) as GDScript).new())
	var terrain: Dictionary = TERRAIN_ONE.duplicate()
	terrain["MaxHealth"] = 2.0
	terrain["PhysAtk"] = 1.5
	var growth: Dictionary = TERRAIN_ONE.duplicate()
	for field: String in growth.keys():
		growth[field] = 0.0
	growth["MaxHealth"] = 0.1
	var scaled: Array = manager.call("_scale_monsters", [monster, null], terrain, growth, 4)
	assert_eq(scaled.size(), 1, "空值必须被跳过，只保留一只怪物。")
	var result: Resource = scaled[0]
	assert_true(result != null, "缩放结果不得为空。")
	assert_eq(
		(result.get_script() as Script).resource_path,
		MONSTER_DATA_GD,
		"缩放结果必须仍是 GDScript 怪物资源。"
	)
	assert_eq(result.get("MonsterName"), monster.get("MonsterName"), "怪物名必须原样保留。")
	assert_eq(result.get("ElementalProperty"), monster.get("ElementalProperty"), "五行属性必须原样保留。")
	assert_eq(result.get("SkillSet"), monster.get("SkillSet"), "技能集合必须原样保留。")
	var attributes: Resource = result.get("InitialAttributes")
	assert_true(attributes != null, "缩放结果必须带初始属性。")
	assert_eq(
		(attributes.get_script() as Script).resource_path,
		STARTING_STATS_GD,
		"缩放后的初始属性必须是 GDScript StartingStats。"
	)
	assert_eq(float(attributes.get("BasePhysAtk")), 120.0, "枯木精 BasePhysAtk 必须按 80 * 1.5 * 1.0 缩放。")
	assert_eq(float(attributes.get("BaseMaxHealth")), 2600.0, "缺省 BaseMaxHealth 必须按 1000 * 2.0 * 1.3 缩放。")
	assert_eq(float(attributes.get("PhysAtkGrowth")), 25.0, "成长字段必须保持旧 C# 缺省值。")
	assert_eq(float(attributes.get("BaseSpeed")), 105.0, "未配置倍率的字段必须保持原值。")
	assert_true(monster.get("InitialAttributes") != attributes, "缩放不得改写入参怪物的属性资源。")
