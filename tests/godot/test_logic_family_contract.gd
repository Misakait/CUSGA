@tool
extends McpTestSuite

## 剩余逻辑族（升级规则 / 玩家数据策略 / 怪物倍率 / 遭遇缩放 / 通道边）迁移契约套件。
##
## 锁定 5 个旧 C# 类型的 GDScript 等价关系：
## 1）UpgradeService -> core/progression/player_progression.gd 的升级规则常量与 _get_value / _get_cost；
## 2）PlayerDataPolicy -> player_wallet.gd 与 player_progression.gd 的 PersistAcrossRuns 开关；
## 3）MonsterStatMultiplier -> encounter_manager.gd 的六字段字典协议与 _identity_multiplier；
## 4）EncounterMonsterScaler -> encounter_manager.gd 的 _build_day_multiplier / _scale_stats / _scale_float；
## 5）PassageGuardEdge -> core/map/passage_guard_state.gd 的 _edge_key 无向边规范化。
## 本批不新增生产脚本，只把数值表、公式与「零生产依赖」钉成断言。
## ComponentLookup 的等价物已由 tests/godot/test_status_component_contract.gd 覆盖，本套件不重复。

## 本批 5 个旧 C# 兼容垫片路径。
const UPGRADE_SERVICE_CS: String = "res://core/progression/UpgradeService.cs"
const PLAYER_DATA_POLICY_CS: String = "res://core/progression/PlayerDataPolicy.cs"
const MONSTER_STAT_MULTIPLIER_CS: String = "res://resources/encounters/MonsterStatMultiplier.cs"
const ENCOUNTER_MONSTER_SCALER_CS: String = "res://core/application/EncounterMonsterScaler.cs"
const PASSAGE_GUARD_EDGE_CS: String = "res://core/map/PassageGuardEdge.cs"

## 迁移期 C# 可选助手：C# 退役后 C# 对照断言自动退场，GDScript 侧断言照跑。
## 说明见 tests/godot/csharp_optional.gd。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## 生产 GDScript 等价物路径。
const PLAYER_PROGRESSION_GD: String = "res://core/progression/player_progression.gd"
const PLAYER_WALLET_GD: String = "res://core/autoloads/player_wallet.gd"
const ENCOUNTER_MANAGER_GD: String = "res://core/application/encounter_manager.gd"
const PASSAGE_GUARD_STATE_GD: String = "res://core/map/passage_guard_state.gd"
const STARTING_STATS_CS: String = "res://resources/stats/StartingStats.cs"
const STARTING_STATS_GD: String = "res://resources/stats/starting_stats.gd"
const TERRAIN_INSTANCE_GD: String = "res://resources/interaction/terrain_instance.gd"

## 六字段倍率协议顺序（等价旧 C# MonsterStatMultiplier 属性顺序）。
const MULTIPLIER_FIELDS: Array = [
	"MaxHealth", "PhysAtk", "PhysDef", "MagPower", "MagResist", "Speed",
]

## 需要保持「零生产引用」的旧类型名与路径。
const LEGACY_NAMES: Array = [
	"UpgradeService", "PlayerDataPolicy", "MonsterStatMultiplier",
	"EncounterMonsterScaler", "PassageGuardEdge",
]
const LEGACY_FILES: Array = [
	UPGRADE_SERVICE_CS, PLAYER_DATA_POLICY_CS, MONSTER_STAT_MULTIPLIER_CS,
	ENCOUNTER_MONSTER_SCALER_CS, PASSAGE_GUARD_EDGE_CS,
]
## 生产根目录（不含 tests：测试文件允许引用旧路径作为对照）。
const PRODUCTION_ROOTS: Array = [
	"res://core", "res://entities", "res://resources", "res://scripts", "res://scenes",
]


func suite_name() -> String:
	return "logic_family_contract"


# ----- 解析与扫描助手 -----

## 读取文本文件内容（先探存在性，避免 C# 退役后读缺失路径刷错误日志）。
##
## 参数 path：res:// 路径。
## 返回值：文件正文；文件缺失或读取失败时返回空字符串。
func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## 去掉 GDScript 注释，保留字符串字面量与换行。
##
## 参数 text：GDScript 源码。
## 返回值：注释被移除的源码，避免文档注释被误判成依赖。
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


## 解析 C# 里 `const int NAME = VALUE;` 的整数值。
##
## 参数 text：C# 源码。
## 参数 name：常量名。
## 返回值：常量值；缺失时返回哨兵 -2147483647 让断言直接失败。
func _csharp_const_int(text: String, name: String) -> int:
	var marker: String = "const int " + name + " = "
	var start: int = text.find(marker)
	if start == -1:
		return -2147483647
	var value_start: int = start + marker.length()
	var value_end: int = text.find(";", value_start)
	if value_end == -1:
		return -2147483647
	return int(text.substr(value_start, value_end - value_start).strip_edges())


## 解析 C# 里 `readonly int[] NAME = [a, b, c];` 的整型数组。
##
## 参数 text：C# 源码。
## 参数 name：数组字段名。
## 返回值：整数数组；缺失时返回空数组。
func _csharp_int_array(text: String, name: String) -> Array:
	var marker: String = "readonly int[] " + name + " = ["
	var start: int = text.find(marker)
	if start == -1:
		return []
	var value_start: int = start + marker.length()
	var value_end: int = text.find("]", value_start)
	if value_end == -1:
		return []
	var out: Array = []
	for piece: String in text.substr(value_start, value_end - value_start).split(","):
		var trimmed: String = piece.strip_edges()
		if trimmed != "":
			out.append(int(trimmed))
	return out


## 按出现顺序解析 C# 属性名。
##
## 参数 text：C# 源码。
## 参数 marker：属性前缀（例如 public float ）。
## 返回值：按源码顺序排列的属性名数组。
func _csharp_property_order(text: String, marker: String) -> Array:
	var out: Array = []
	var cursor: int = 0
	while true:
		var start: int = text.find(marker, cursor)
		if start == -1:
			break
		var name_start: int = start + marker.length()
		var name_end: int = text.find(" ", name_start)
		if name_end == -1:
			break
		out.append(text.substr(name_start, name_end - name_start))
		cursor = name_end
	return out


## 解析属性读取默认值表。
##
## 参数 text：源码正文（C# 用 ReadStat(source, "X", 1f)，GDScript 用 _read_stat(source, "X", 1.0)）。
## 参数 marker：调用前缀。
## 返回值：字段名到默认值的字典；省略的 fallback 按旧 C# 的 0 处理。
func _read_stat_defaults(text: String, marker: String) -> Dictionary:
	var out: Dictionary = {}
	var cursor: int = 0
	while true:
		var start: int = text.find(marker, cursor)
		if start == -1:
			break
		var name_start: int = start + marker.length()
		var name_end: int = text.find("\"", name_start)
		if name_end == -1:
			break
		var field: String = text.substr(name_start, name_end - name_start)
		var close_index: int = text.find(")", name_end)
		if close_index == -1:
			break
		var tail: String = text.substr(name_end, close_index - name_end)
		var default_value: float = 0.0
		var comma_index: int = tail.rfind(",")
		if comma_index != -1:
			default_value = float(tail.substr(comma_index + 1).strip_edges().trim_suffix("f"))
		out[field] = default_value
		cursor = close_index
	return out


## 解析 C# `[Export] public float NAME { get; set; } = VALUEF;` 的默认值表。
##
## 参数 text：C# 源码。
## 返回值：字段名到默认值的字典。
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


## 递归扫描指定扩展名的文件里是否出现目标文本。
##
## 参数 directory：起始目录。
## 参数 needle：目标文本。
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
			if text.find(needle) != -1:
				hits.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return hits

# ----- 升级规则（旧 C# UpgradeService） -----

## 升级规则常量表必须与旧 C# UpgradeService 同值。
func test_upgrade_rule_table_parity() -> void:
	assert_true(ResourceLoader.exists(PLAYER_PROGRESSION_GD), "生产 player_progression.gd 必须存在。")
	var constants: Dictionary = (load(PLAYER_PROGRESSION_GD) as GDScript).get_script_constant_map()
	assert_eq(constants.get("WarehouseCosts", []), [300, 600, 1000], "生产仓库费用表必须与旧 C# 同值。")
	assert_eq(constants.get("CarryCosts", []), [200, 350, 550, 800, 1100], "生产带入栏费用表必须与旧 C# 同值。")
	# C# 对照部分：垫片退役后整段退场，上面的 GDScript 断言仍照跑。
	var cs: String = _read(UPGRADE_SERVICE_CS)
	if cs.is_empty():
		return
	for constant_name: String in [
		"WarehouseBaseValue", "WarehouseValuePerLevel", "WarehouseMaxLevel",
		"CarryBaseValue", "CarryValuePerLevel", "CarryMaxLevel",
	]:
		assert_eq(
			_csharp_const_int(cs, constant_name),
			int(constants.get(constant_name, -1)),
			"升级规则常量 %s 必须与旧 C# UpgradeService 同值。" % constant_name
		)
	assert_eq(_csharp_int_array(cs, "WarehouseCosts"), [300, 600, 1000], "旧 C# 仓库费用表必须保持。")
	assert_eq(_csharp_int_array(cs, "CarryCosts"), [200, 350, 550, 800, 1100], "旧 C# 带入栏费用表必须保持。")
	assert_true(
		cs.contains("public static int GetRemainingTotalCost(UpgradeKind kind, int level)"),
		"C# 垫片的剩余总价入口必须保留。"
	)
	assert_false(
		_strip_gd_comments(_read(PLAYER_PROGRESSION_GD)).contains("GetRemainingTotalCost"),
		"生产 GDScript 没有剩余总价消费方，不得凭空新增同名入口。"
	)


## 升级规则运行行为必须与旧 C# 公式一致。
func test_upgrade_rule_runtime_behaviour_parity() -> void:
	var progression: Node = track((load(PLAYER_PROGRESSION_GD) as GDScript).new())
	assert_true(progression != null, "player_progression.gd 必须可实例化。")
	assert_eq(progression.call("_get_value", 0, 0), 27, "仓库 0 级容量必须等于旧 C# 的 27。")
	assert_eq(progression.call("_get_value", 0, 3), 54, "仓库满级容量必须等于旧 C# 的 27 + 9 * 3。")
	assert_eq(progression.call("_get_value", 1, 0), 5, "带入栏 0 级数量必须等于旧 C# 的 5。")
	assert_eq(progression.call("_get_value", 1, 5), 10, "带入栏满级数量必须等于旧 C# 的 5 + 1 * 5。")
	assert_eq(progression.call("_get_value", 0, 99), 54, "越界等级必须按旧 C# Math.Clamp 收窄到上限。")
	assert_eq(progression.call("_get_value", 0, -3), 27, "负数等级必须按旧 C# Math.Clamp 收窄到 0。")
	assert_eq(progression.call("_get_cost", 0, 0), 300, "仓库 0->1 费用必须等于旧 C#。")
	assert_eq(progression.call("_get_cost", 0, 2), 1000, "仓库 2->3 费用必须等于旧 C#。")
	assert_eq(progression.call("_get_cost", 0, 3), 0, "满级费用必须为 0，与旧 C# GetCost 一致。")
	assert_eq(progression.call("_get_cost", 1, 4), 1100, "带入栏 4->5 费用必须等于旧 C#。")
	assert_eq(progression.call("_is_max_level", 0, 3), true, "仓库 3 级必须判定满级。")
	assert_eq(progression.call("_is_max_level", 1, 4), false, "带入栏 4 级不得判定满级。")
	assert_eq(progression.call("_clamp_level", 1, 9), 5, "等级上限收窄必须与旧 C# ClampLevel 一致。")


# ----- 玩家数据策略（旧 C# PlayerDataPolicy） -----

## 持久化开关必须三处同值（C# 垫片 + 钱包 + 升级）。
func test_player_data_policy_switch_parity() -> void:
	var cs: String = _read(PLAYER_DATA_POLICY_CS)
	if not cs.is_empty():
		assert_true(
			cs.contains("public const bool PersistAcrossRuns = false;"),
			"旧 C# PlayerDataPolicy 的开关必须保持 false。"
		)
	for entry: Array in [
		[PLAYER_WALLET_GD, "钱包"],
		[PLAYER_PROGRESSION_GD, "升级"],
	]:
		var path: String = entry[0]
		var label: String = entry[1]
		var code: String = _strip_gd_comments(_read(path))
		assert_true(
			code.contains("const PersistAcrossRuns: bool = false"),
			"%s 生产脚本必须保留 PersistAcrossRuns = false。" % label
		)
		assert_true(
			code.contains("if not PersistAcrossRuns"),
			"%s 生产脚本必须按开关跳过读档或写档。" % label
		)
		assert_eq(
			(load(path) as GDScript).get_script_constant_map().get("PersistAcrossRuns", true),
			false,
			"%s 生产脚本开关的运行时取值必须为 false。" % label
			)

# ----- 怪物倍率协议（旧 C# MonsterStatMultiplier） -----

## 六字段倍率协议与中性倍率必须与旧 C# 一致。
func test_monster_stat_multiplier_protocol_parity() -> void:
	var cs: String = _read(MONSTER_STAT_MULTIPLIER_CS)
	if not cs.is_empty():
		assert_eq(
			_csharp_property_order(cs, "public float "),
			MULTIPLIER_FIELDS,
			"旧 C# MonsterStatMultiplier 的字段顺序必须保持。"
		)
		assert_eq(cs.count("= 1f;"), 6, "旧 C# Identity 的六个字段必须全部为 1。")
		assert_true(cs.contains("public static MonsterStatMultiplier Identity"), "旧 C# Identity 静态属性必须保留。")
	var terrain_code: String = _strip_gd_comments(_read(TERRAIN_INSTANCE_GD))
	assert_true(
		terrain_code.contains("func GetEncounterVarianceSnapshot"),
		"地形实例必须保留倍率快照协议，等价旧 C# EncounterVarianceMultiplier。"
	)
	var manager: Node = track((load(ENCOUNTER_MANAGER_GD) as GDScript).new())
	var manager_code: String = _strip_gd_comments(_read(ENCOUNTER_MANAGER_GD))
	assert_true(manager_code.contains("const MULTIPLIER_FIELDS: Array[String] = ["), "生产侧必须声明倍率字段集合。")
	assert_eq(
		manager.call("_identity_multiplier").keys(),
		MULTIPLIER_FIELDS,
		"生产中性倍率字典的键顺序必须与旧 C# 字段顺序一致。"
	)
	for field: String in MULTIPLIER_FIELDS:
		assert_eq(
			float(manager.call("_identity_multiplier")[field]),
			1.0,
			"中性倍率 %s 必须为 1。" % field
		)
	assert_eq(
		manager.call("_build_per_day_growth_multiplier").keys(),
		MULTIPLIER_FIELDS,
		"每日成长率字典必须覆盖同样六个字段。"
	)
	for field: String in MULTIPLIER_FIELDS:
		assert_eq(
			float(manager.call("_build_per_day_growth_multiplier")[field]),
			0.0,
			"每日成长率 %s 的默认值必须为 0。" % field
		)


# ----- 遭遇缩放（旧 C# EncounterMonsterScaler） -----

## 缩放字段表、缺省值与公式必须与旧 C# 一致。
func test_encounter_monster_scaler_formula_parity() -> void:
	var cs: String = _read(ENCOUNTER_MONSTER_SCALER_CS)
	var cs_defaults: Dictionary = _read_stat_defaults(cs, "ReadStat(source, \"")
	var gd_code: String = _strip_gd_comments(_read(ENCOUNTER_MANAGER_GD))
	var gd_defaults: Dictionary = _read_stat_defaults(gd_code, "_read_stat(source, \"")
	var stats_gd: String = _read(STARTING_STATS_GD)
	# GDScript 侧不变量：镜像必须覆盖生产缩放用到的每一个字段。
	for field: String in gd_defaults.keys():
		assert_true(
			stats_gd.contains("var " + field + ":"),
			"StartingStats 的 GDScript 镜像必须含字段 %s，供后续 StartingStats 批次切换。" % field
		)
	# C# 对照部分：垫片退役后整段退场。
	if not cs.is_empty():
		assert_eq(cs_defaults.size(), 30, "旧 C# ScaleStats 必须覆盖 30 个属性字段。")
		assert_eq(gd_defaults.size(), cs_defaults.size(), "生产缩放的字段数量必须与旧 C# 一致。")
		var stats_defaults: Dictionary = _csharp_export_defaults(_read(STARTING_STATS_CS))
		assert_eq(stats_defaults.size(), 30, "旧 C# StartingStats 必须保留 30 个字段。")
		for field: String in cs_defaults.keys():
			assert_true(gd_defaults.has(field), "生产缩放必须覆盖字段 %s。" % field)
			assert_eq(
				float(gd_defaults.get(field, -1.0)),
				float(cs_defaults[field]),
				"字段 %s 的缩放缺省值必须与旧 C# 相同。" % field
			)
			assert_eq(
				float(cs_defaults[field]),
				float(stats_defaults.get(field, -1.0)),
				"字段 %s 的缩放缺省值必须等于旧 C# StartingStats 的字段默认值。" % field
			)
		assert_true(cs.contains("int elapsedDays = Math.Max(currentDay - 1, 0);"), "旧 C# 以第 1 天为无成长基准。")
		assert_true(cs.contains("return value * terrainMultiplier * dayMultiplier;"), "旧 C# ScaleFloat 公式必须保持。")
	assert_true(
		gd_code.contains("var elapsed_days: int = maxi(current_day - 1, 0)"),
		"生产天数基准必须与旧 C# BuildDayMultiplier 相同。"
	)
	assert_true(
		gd_code.contains("return value * terrain_multiplier * day_multiplier"),
		"生产缩放公式必须与旧 C# ScaleFloat 相同。"
	)
	assert_true(
		gd_code.contains("var scaled: Resource = STARTING_STATS_SCRIPT.new()"),
		"生产缩放必须构造 GDScript StartingStats 资源，旧 C# StartingStats 只作兼容输入。"
	)
	var manager: Node = track((load(ENCOUNTER_MANAGER_GD) as GDScript).new())
	var day_four: Dictionary = manager.call("_build_day_multiplier", {"MaxHealth": 0.1}, 4)
	assert_eq(float(day_four["MaxHealth"]), 1.3, "第 4 天生命成长乘数必须等于 1 + 3 * 0.1。")
	assert_eq(float(day_four["PhysAtk"]), 1.0, "未配置成长率的字段必须保持中性乘数。")
	assert_eq(
		float(manager.call("_build_day_multiplier", {"MaxHealth": 0.5}, 1)["MaxHealth"]),
		1.0,
		"第 1 天不得产生成长。"
	)
	assert_eq(
		float(manager.call("_build_day_multiplier", {"MaxHealth": 0.5}, 0)["MaxHealth"]),
		1.0,
		"第 0 天必须被 maxi 收窄为无成长。"
	)
	assert_eq(manager.call("_scale_float", 100.0, 1.5, 2.0), 300.0, "缩放公式必须等于 value * terrain * day。")


# ----- 无向通道边（旧 C# PassageGuardEdge） -----

## 端点规范化与无向语义必须与旧 C# PassageGuardEdge 一致。
func test_passage_guard_edge_normalization_parity() -> void:
	var cs: String = _read(PASSAGE_GUARD_EDGE_CS)
	if not cs.is_empty():
		assert_true(
			cs.contains("public static PassageGuardEdge From(Vector2I first, Vector2I second)"),
			"旧 C# PassageGuardEdge 的 From 工厂必须保留。"
		)
		assert_true(cs.contains("int xCompare = left.X.CompareTo(right.X);"), "旧 C# 规范化必须先比 X、再比 Y。")
	var code: String = _strip_gd_comments(_read(PASSAGE_GUARD_STATE_GD))
	assert_true(
		code.contains("func _compare_points(left: Vector2i, right: Vector2i) -> int"),
		"生产侧必须保留同一比较函数。"
	)
	assert_true(code.contains("if left.x != right.x:"), "生产比较必须同样先比 X。")
	assert_true(
		code.contains('return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]'),
		"生产边键格式必须保持端点顺序稳定。"
	)
	var state: RefCounted = (load(PASSAGE_GUARD_STATE_GD) as GDScript).new()
	state.call("AddGuard", Vector2i(3, 4), Vector2i(1, 2))
	assert_eq(state.get("Count"), 1, "同一条无向边只能占一个键。")
	assert_eq(state.call("IsGuarded", Vector2i(1, 2), Vector2i(3, 4)), true, "正向查询必须命中。")
	assert_eq(state.call("IsGuarded", Vector2i(3, 4), Vector2i(1, 2)), true, "反向查询必须命中同一条边。")
	assert_eq(state.call("IsGuarded", Vector2i(1, 3), Vector2i(3, 4)), false, "不同边不得命中。")
	state.call("AddGuard", Vector2i(1, 2), Vector2i(3, 4))
	assert_eq(state.get("Count"), 1, "反向重复标记不得新增键。")
	state.call("ClearGuard", Vector2i(3, 4), Vector2i(1, 2))
	assert_eq(state.get("Count"), 0, "反向清除必须移除同一条边。")
	state.call("AddGuard", Vector2i(2, 9), Vector2i(2, 3))
	assert_eq(state.get("Count"), 1, "X 相同而 Y 不同的端点必须视为另一条边。")
	state.call("ClearAll")
	assert_eq(state.get("Count"), 0, "ClearAll 必须清空全部驻守通道。")


# ----- 资产与生产依赖扫描 -----

## 5 个旧类型不得出现在资产里，也不得被生产 GDScript 加载；垫片本身必须保留。
func test_assets_and_code_have_no_legacy_dependency() -> void:
	var asset_hits: Array = []
	for legacy_name: String in LEGACY_NAMES:
		asset_hits.append_array(_scan("res://scenes", legacy_name, ["tscn", "tres", "res"]))
		asset_hits.append_array(_scan("res://resources", legacy_name, ["tscn", "tres", "res"]))
	assert_eq(asset_hits, [], "资产不得再引用本批 5 个旧 C# 类型名：%s" % str(asset_hits))
	var path_hits: Array = []
	for root: String in PRODUCTION_ROOTS:
		for legacy_path: String in LEGACY_FILES:
			path_hits.append_array(_scan(root, legacy_path.trim_prefix("res://"), ["gd"], true))
	assert_eq(path_hits, [], "生产 GDScript 不得加载旧 C# 路径：%s" % str(path_hits))
	# 垫片保留断言只在垫片仍在时成立；C# 退役后这段随之退场。
	if CS_OPTIONAL.present_all(LEGACY_FILES):
		for legacy_path: String in LEGACY_FILES:
			assert_true(ResourceLoader.exists(legacy_path), "旧 C# 垫片 %s 必须保留到全量迁移完成。" % legacy_path)
