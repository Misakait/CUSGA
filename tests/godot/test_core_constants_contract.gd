@tool
extends McpTestSuite

## 核心常量族迁移契约套件。
##
## 锁定 core/constants 下 5 个旧 C# 常量文件（CombatConstants / ElementType / GDSignals /
## TagConsts / TimeCosts）的 GDScript 等价载体：取值与旧 C# 逐条一致，并与 GDScript 生产
## 消费方自带的常量 / 字面量逐值对齐；同时用运行时读取锁定载体本身的取值面。
## 旧 C# 常量类继续保留给未迁移的 C# 消费方，全量迁移完成前不得删除；
## 迁移完成后本节依赖 CS_OPTIONAL 自动退场（见 tests/godot/csharp_optional.gd）。

## 本批新增的 GDScript 常量载体。
const COMBAT_CONSTANTS_GD: String = "res://core/constants/combat_constants.gd"
const ELEMENT_TYPE_GD: String = "res://core/constants/element_type.gd"
const GD_SIGNALS_GD: String = "res://core/constants/gd_signals.gd"
const TAG_CONSTS_GD: String = "res://core/constants/tag_consts.gd"
const TIME_COSTS_GD: String = "res://core/constants/time_costs.gd"

## 与上面逐项对应的旧 C# 常量文件。
const COMBAT_CONSTANTS_CS: String = "res://core/constants/CombatConstants.cs"
const ELEMENT_TYPE_CS: String = "res://core/constants/ElementType.cs"
const GD_SIGNALS_CS: String = "res://core/constants/GDSignals.cs"
const TAG_CONSTS_CS: String = "res://core/constants/TagConsts.cs"
const TIME_COSTS_CS: String = "res://core/constants/TimeCosts.cs"

## 迁移期 C# 可选助手：C# 退役后 C# 对照断言自动退场，GDScript 侧断言照跑。
## 说明见 tests/godot/csharp_optional.gd。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## GDScript 生产消费方。
const DAMAGE_FORMULA_GD: String = "res://core/combat/damage_formula.gd"
const DAMAGE_PAYLOAD_GD: String = "res://core/combat/damage_payload.gd"
const ELEMENTAL_SYSTEM_GD: String = "res://core/combat/elemental_system.gd"
const TIME_SYSTEM_GD: String = "res://core/autoloads/time_system.gd"
const GLOBAL_EVENT_BUS_GD: String = "res://core/autoloads/GlobalEventBus.gd"
const INVENTORY_COMPONENT_GD: String = "res://entities/components/inventory_component.gd"
const WAREHOUSE_COMPONENT_GD: String = "res://entities/components/warehouse_inventory_component.gd"
const BATTLE_DECK_COMPONENT_GD: String = "res://entities/components/battle_deck_component.gd"
const EQUIPMENT_COMPONENT_GD: String = "res://entities/components/equipment_component.gd"
const DRAGGABLE_DATA_GD: String = "res://core/ui/draggable/draggable_data.gd"
const EQUIPMENT_SLOT_UI_GD: String = "res://core/ui/equipment_slot_ui.gd"
const MAP_INSTANTIATOR_GD: String = "res://scripts/map_scripts/map_instantiator.gd"

## 五行属性逐条对照：[枚举成员, 枚举值, GDScript 常量后缀]。
const ELEMENT_ROWS: Array = [
	["None", 0, "NONE"],
	["Wood", 1, "WOOD"],
	["Metal", 2, "METAL"],
	["Water", 3, "WATER"],
	["Earth", 4, "EARTH"],
	["Fire", 5, "FIRE"],
]

## 信号名逐条对照：[旧 C# 成员名, 信号名字符串, GDScript 声明所在脚本]。
const SIGNAL_ROWS: Array = [
	["OnPlayerAcquiredTalent", "on_player_acquired_talent", GLOBAL_EVENT_BUS_GD],
	["OnStatusChanged", "on_status_changed", GLOBAL_EVENT_BUS_GD],
	["OnEntityDropped", "on_entity_dropped", GLOBAL_EVENT_BUS_GD],
	["OnEnteredVault", "on_entered_vault", GLOBAL_EVENT_BUS_GD],
	["OnEnteredRoom", "on_entered_room", MAP_INSTANTIATOR_GD],
]

## 标签逐条对照：[旧 C# 成员名, 标签字符串, 生产消费方脚本（空串表示当前无消费方）]。
const TAG_ROWS: Array = [
	["SystemInventory", "SystemInventory", INVENTORY_COMPONENT_GD],
	["SystemWarehouse", "SystemWarehouse", WAREHOUSE_COMPONENT_GD],
	["SystemBattleDeck", "SystemBattleDeck", BATTLE_DECK_COMPONENT_GD],
	["SystemEquipment", "SystemEquipment", EQUIPMENT_COMPONENT_GD],
	["WoodDamageUp", "WoodDamageUp", ""],
	["HealAfterAction", "HealAfterAction", ""],
	["MagicItem", "MagicItem", EQUIPMENT_COMPONENT_GD],
]

## 时间消耗逐条对照：[旧 C# 成员名, 取值, 生产消费方片段（空串表示当前无消费方）]。
const TIME_ROWS: Array = [
	["MapMove", 10, "@export var MapMoveTimeCost: int = 10"],
	["EnterScene", 5, ""],
	["ChopTree", 20, ""],
	["PlantSeed", 10, ""],
]

## 当前两语言都没有消费方的常量：[标识符, 唯一允许命中的文件]。
const UNUSED_CONSTANTS: Array = [
	["WoodDamageUp", TAG_CONSTS_GD],
	["HealAfterAction", TAG_CONSTS_GD],
	["EnterScene", TIME_COSTS_GD],
	["ChopTree", TIME_COSTS_GD],
	["PlantSeed", TIME_COSTS_GD],
]


## 返回 GodotAI 使用的稳定套件名称。
##
## @return 核心常量族契约套件名。
func suite_name() -> String:
	return "core_constants_contract"


## 验证 5 个常量载体的文件形状。
##
## @return 无返回值。
func test_carrier_shape() -> void:
	for path: String in [
		COMBAT_CONSTANTS_GD,
		ELEMENT_TYPE_GD,
		GD_SIGNALS_GD,
		TAG_CONSTS_GD,
		TIME_COSTS_GD,
	]:
		assert_true(FileAccess.file_exists(path), "常量载体必须存在：%s" % path)
		var text: String = FileAccess.get_file_as_string(path)
		assert_true(text.begins_with("extends RefCounted"), "常量载体必须继承 RefCounted：%s" % path)
		assert_false(_declares_class_name(text), "常量载体不得声明 class_name：%s" % path)
		assert_false(text.contains("TODO"), "常量载体不得保留 TODO 占位：%s" % path)


## 验证伤害公式常数与旧 C#、生产消费方逐值一致。
##
## @return 无返回值。
func test_combat_constant_matches_legacy_and_consumer() -> void:
	var legacy: String = CS_OPTIONAL.read(COMBAT_CONSTANTS_CS)
	assert_true(
		FileAccess.get_file_as_string(COMBAT_CONSTANTS_GD).contains("const DAMAGE_FORMULA_CONSTANT: float = 100.0"),
		"GDScript 载体必须保留同值常数 DAMAGE_FORMULA_CONSTANT = 100.0。"
	)
	assert_eq(
		float((load(COMBAT_CONSTANTS_GD) as GDScript).get_script_constant_map().get("DAMAGE_FORMULA_CONSTANT", -1.0)),
		100.0,
		"载体运行时取值必须等于旧 C# 的 100f。"
	)
	if not legacy.is_empty():
		assert_true(
			legacy.contains("public const float DamageFormulaConstant = 100f;"),
			"旧 C# 伤害公式常数必须仍是 100f。"
		)

## 判断脚本文本是否声明 class_name。
##
## @param text GDScript 全文。
## @return 存在顶层 class_name 声明时返回 true。
func _declares_class_name(text: String) -> bool:
	for raw_line: String in text.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.begins_with("class_name"):
			return true

	return false


## 递归扫描目录下 .gd 文本中的标识符引用。
##
## @param directory 起始目录的 res:// 路径。
## @param needle 待匹配标识符。
## @return 命中文件的 res:// 路径数组。
func _grep_gd_references(directory: String, needle: String) -> Array[String]:
	var offenders: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return offenders

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				offenders.append_array(_grep_gd_references("%s/%s" % [directory, entry], needle))
		elif entry.ends_with(".gd"):
			var path := "%s/%s" % [directory, entry]
			if FileAccess.get_file_as_string(path).contains(needle):
				offenders.append(path)
		entry = dir.get_next()

	dir.list_dir_end()
	return offenders

## 验证五行属性枚举与旧 C#、GDScript 消费方逐值一致。
##
## @return 无返回值。
func test_element_type_matches_legacy_and_consumers() -> void:
	var legacy: String = CS_OPTIONAL.read(ELEMENT_TYPE_CS)
	var carrier: String = FileAccess.get_file_as_string(ELEMENT_TYPE_GD)
	var payload: String = FileAccess.get_file_as_string(DAMAGE_PAYLOAD_GD)
	var elemental: String = FileAccess.get_file_as_string(ELEMENTAL_SYSTEM_GD)

	var enum_map: Variant = load(ELEMENT_TYPE_GD).get_script_constant_map().get("ElementType")
	assert_true(enum_map is Dictionary, "载体必须导出 ElementType 枚举。")
	var values: Dictionary = enum_map
	assert_eq(values.size(), 6, "五行枚举必须是 6 项。")

	for row: Array in ELEMENT_ROWS:
		var member: String = str(row[0])
		var value: int = int(row[1])
		var suffix: String = str(row[2])

		if not legacy.is_empty():
			assert_true(
				legacy.contains("%s = %d" % [member, value]), "旧 C# 枚举必须保留取值：%s" % member
			)
		assert_true(
			carrier.contains("%s = %d" % [member, value]), "GDScript 枚举必须保留取值：%s" % member
		)
		assert_eq(int(values.get(member)), value, "载体运行时取值必须正确：%s" % member)
		assert_true(
			payload.contains("const ELEMENT_%s: int = %d" % [suffix, value]),
			"伤害载荷必须保留同值常量：%s" % suffix
		)
		assert_true(
			elemental.contains("const ELEMENT_%s: int = %d" % [suffix, value]),
			"元素相克系统必须保留同值常量：%s" % suffix
		)


## 验证全局信号名与旧 C#、事件总线声明逐字一致。
##
## @return 无返回值。
func test_signal_names_match_legacy_and_bus() -> void:
	var legacy: String = CS_OPTIONAL.read(GD_SIGNALS_CS)
	var carrier: String = FileAccess.get_file_as_string(GD_SIGNALS_GD)
	var constants: Variant = load(GD_SIGNALS_GD).get_script_constant_map()
	assert_true(constants is Dictionary, "信号载体必须导出常量表。")
	var table: Dictionary = constants

	for row: Array in SIGNAL_ROWS:
		var member: String = str(row[0])
		var signal_name: String = str(row[1])
		var owner_path: String = str(row[2])

		if not legacy.is_empty():
			assert_true(
				legacy.contains("new(\"%s\")" % signal_name), "旧 C# 必须保留信号名：%s" % signal_name
			)
		assert_true(
			carrier.contains("const %s: StringName = &\"%s\"" % [member, signal_name]),
			"载体必须保留同名常量：%s" % member
		)
		assert_eq(String(table.get(member)), signal_name, "载体运行时取值必须正确：%s" % member)
		assert_true(
			FileAccess.get_file_as_string(owner_path).contains("signal %s" % signal_name),
			"生产脚本必须声明同名信号：%s" % signal_name
		)

	# 旧 C# 里被注释掉的 on_inventory_toggled 从未生效，载体不得把它带进契约。
	assert_false(carrier.contains("on_inventory_toggled"), "未生效的旧信号不得迁移。")


## 验证拖拽 / 玩法标签与旧 C#、生产消费方逐字一致。
##
## @return 无返回值。
func test_tag_consts_match_legacy_and_consumers() -> void:
	var legacy: String = CS_OPTIONAL.read(TAG_CONSTS_CS)
	var carrier: String = FileAccess.get_file_as_string(TAG_CONSTS_GD)
	var constants: Variant = load(TAG_CONSTS_GD).get_script_constant_map()
	assert_true(constants is Dictionary, "标签载体必须导出常量表。")
	var table: Dictionary = constants
	assert_eq(table.size(), 7, "标签常量必须是 7 项。")

	for row: Array in TAG_ROWS:
		var member: String = str(row[0])
		var tag: String = str(row[1])
		var consumer: String = str(row[2])

		if not legacy.is_empty():
			assert_true(legacy.contains("new(\"%s\")" % tag), "旧 C# 必须保留标签：%s" % tag)
		assert_true(
			carrier.contains("const %s: StringName = &\"%s\"" % [member, tag]),
			"载体必须保留同名常量：%s" % member
		)
		assert_eq(String(table.get(member)), tag, "载体运行时取值必须正确：%s" % member)

		if not consumer.is_empty():
			assert_true(
				FileAccess.get_file_as_string(consumer).contains("&\"%s\"" % tag),
				"生产消费方必须保留同名标签：%s" % tag
			)

	# 拖拽数据默认来源与装备槽拖拽来源也必须同值。
	assert_true(
		FileAccess.get_file_as_string(DRAGGABLE_DATA_GD).contains(
			"var SourceSystem: StringName = &\"SystemInventory\""
		),
		"拖拽数据默认来源必须仍是背包。"
	)
	assert_true(
		FileAccess.get_file_as_string(EQUIPMENT_SLOT_UI_GD).contains(
			"const EQUIPMENT_DRAG_SOURCE: StringName = &\"SystemEquipment\""
		),
		"装备槽拖拽来源必须仍是装备栏。"
	)


## 验证时间消耗常量与旧 C#、时间系统默认值逐值一致。
##
## @return 无返回值。
func test_time_costs_match_legacy_and_consumer() -> void:
	var legacy: String = CS_OPTIONAL.read(TIME_COSTS_CS)
	var carrier: String = FileAccess.get_file_as_string(TIME_COSTS_GD)
	var constants: Variant = load(TIME_COSTS_GD).get_script_constant_map()
	assert_true(constants is Dictionary, "时间消耗载体必须导出常量表。")
	var table: Dictionary = constants
	assert_eq(table.size(), 4, "时间消耗常量必须是 4 项。")

	for row: Array in TIME_ROWS:
		var member: String = str(row[0])
		var value: int = int(row[1])
		var consumer_hint: String = str(row[2])

		if not legacy.is_empty():
			assert_true(
				legacy.contains("public const int %s = %d;" % [member, value]),
				"旧 C# 必须保留取值：%s" % member
			)
		assert_true(
			carrier.contains("const %s: int = %d" % [member, value]), "载体必须保留取值：%s" % member
		)
		assert_eq(int(table.get(member)), value, "载体运行时取值必须正确：%s" % member)

		if not consumer_hint.is_empty():
			assert_true(
				FileAccess.get_file_as_string(TIME_SYSTEM_GD).contains(consumer_hint),
				"时间系统必须保留同一默认值：%s" % member
			)


## 验证当前无消费方的旧常量确实没有任何 .gd 读取方。
##
## 这五项在旧 C# 里也没有读取方（EnterScene / ChopTree / PlantSeed / WoodDamageUp /
## HealAfterAction），最终清理时可随常量类一起删除；这里把「无消费方」变成可执行断言，
## 避免将来新增消费方却忘记把它接进载体。
##
## @return 无返回值。
func test_unused_constants_have_no_consumers() -> void:
	for row: Array in UNUSED_CONSTANTS:
		var needle: String = str(row[0])
		var carrier_path: String = str(row[1])
		var hits: Array[String] = []
		for directory: String in [
			"res://core",
			"res://entities",
			"res://resources",
			"res://scripts",
		]:
			hits.append_array(_grep_gd_references(directory, needle))

		# 载体自身会在注释与常量声明里命中，因此期望恰好只命中载体一次。
		assert_eq(hits, [carrier_path] as Array[String], "%s 当前不允许有生产消费方：%s" % [needle, str(hits)])

	var carrier_script: GDScript = load(COMBAT_CONSTANTS_GD)
	assert_true(carrier_script != null, "战斗常量载体必须可加载。")
	var constant: Variant = carrier_script.get_script_constant_map().get("DAMAGE_FORMULA_CONSTANT")
	assert_true(constant != null, "载体必须导出 DAMAGE_FORMULA_CONSTANT。")
	assert_true(is_equal_approx(float(constant), 100.0), "载体常数必须是 100.0。")

	assert_true(
		FileAccess.get_file_as_string(DAMAGE_FORMULA_GD).contains(
			"const DAMAGE_FORMULA_CONSTANT: float = 100.0"
		),
		"伤害公式脚本必须仍带同值常数。"
	)
