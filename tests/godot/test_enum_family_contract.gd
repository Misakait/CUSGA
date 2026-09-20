@tool
extends McpTestSuite

## 枚举族迁移契约套件。
##
## 锁定 8 个旧 C# 枚举（StatusChangeReason / StackPolicy / DurationTickTiming /
## DurationExpirePolicy / StatusHookPhase / CraftingFailureReason / ShopFailureReason /
## UpgradeKind）的 GDScript 等价载体：成员顺序与取值逐条一致，并与 GDScript 生产消费方
## 自带的常量 / 枚举逐值对齐；SkillTargetingType 的 GDScript 等价物是代码生成产物
## （scripts/generated/SkillTargetingType.gd），本套件同时锁定它的生成边界。
## 旧 C# 枚举继续保留给未迁移的 C# 消费方，全量迁移完成前不得删除；
## C# 物理退役后，C# 侧对照断言经 CS_OPTIONAL 自动退场（见 tests/godot/csharp_optional.gd）。

## 本批新增的 GDScript 枚举载体。
const CARRIER_STATUS_CHANGE_REASON: String = "res://core/combat/status/status_change_reason.gd"
const CARRIER_STACK_POLICY: String = "res://core/combat/status/stack_policy.gd"
const CARRIER_DURATION_TICK_TIMING: String = "res://core/combat/status/duration_tick_timing.gd"
const CARRIER_DURATION_EXPIRE_POLICY: String = "res://core/combat/status/duration_expire_policy.gd"
const CARRIER_STATUS_HOOK_PHASE: String = "res://core/combat/status/status_hook_phase.gd"
const CARRIER_CRAFTING_FAILURE_REASON: String = "res://core/crafting/crafting_failure_reason.gd"
const CARRIER_SHOP_FAILURE_REASON: String = "res://core/shop/shop_failure_reason.gd"
const CARRIER_UPGRADE_KIND: String = "res://core/progression/upgrade_kind.gd"

## 对应的旧 C# 枚举文件。
const LEGACY_STATUS_CHANGE_REASON: String = "res://core/combat/status/StatusChangeReason.cs"
const LEGACY_STACK_POLICY: String = "res://core/combat/status/StackPolicy.cs"
const LEGACY_DURATION_TICK_TIMING: String = "res://core/combat/status/DurationTickTiming.cs"
const LEGACY_DURATION_EXPIRE_POLICY: String = "res://core/combat/status/DurationExpirePolicy.cs"
const LEGACY_STATUS_HOOK_PHASE: String = "res://core/combat/status/StatusHookPhase.cs"
const LEGACY_CRAFTING_FAILURE_REASON: String = "res://core/crafting/CraftingFailureReason.cs"
const LEGACY_SHOP_FAILURE_REASON: String = "res://core/shop/ShopFailureReason.cs"
const LEGACY_UPGRADE_KIND: String = "res://core/progression/UpgradeKind.cs"
const LEGACY_SKILL_TARGETING_TYPE: String = "res://core/combat/skills/SkillTargetingType.cs"

## 迁移期 C# 可选助手：C# 退役后 C# 对照断言自动退场，GDScript 侧断言照跑。
## 说明见 tests/godot/csharp_optional.gd。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## GDScript 生产消费方 / 代码生成产物。
const STATUS_COMPONENT_GD: String = "res://entities/components/status_component.gd"
const STATUS_EFFECT_INSTANCE_GD: String = "res://core/combat/status/status_effect_instance.gd"
const CRAFTING_SERVICE_GD: String = "res://core/crafting/crafting_service.gd"
const CRAFTING_COMPONENT_GD: String = "res://entities/components/crafting_component.gd"
const SHOP_SERVICE_GD: String = "res://core/shop/shop_service.gd"
const SHOP_CONTROL_GD: String = "res://scripts/shop/shop_control.gd"
const GENERATED_SKILL_TARGETING_TYPE_GD: String = "res://scripts/generated/SkillTargetingType.gd"
const SKILL_TARGETING_CODEGEN_GD: String = "res://addons/skill_targeting_type_codegen/skill_targeting_type_codegen.gd"
const CARD_MANAGER_GD: String = "res://scripts/card_scripts/card_manager.gd"
const BATTLE_MANAGER_GD: String = "res://scripts/battle_scripts/battle_manager.gd"
const PLAYER_PROGRESSION_GD: String = "res://core/progression/player_progression.gd"

## 每个枚举：[枚举名, GDScript 载体, 旧 C# 文件, [[成员名, 取值], …]]。
const ENUM_ROWS: Array = [
	[
		"StatusChangeReason",
		CARRIER_STATUS_CHANGE_REASON,
		LEGACY_STATUS_CHANGE_REASON,
		[
			["Applied", 0],
			["Removed", 1],
			["Refreshed", 2],
			["StackChanged", 3],
			["DurationTicked", 4],
			["StackExpired", 5],
			["Cleared", 6],
		],
	],
	[
		"StackPolicy",
		CARRIER_STACK_POLICY,
		LEGACY_STACK_POLICY,
		[["ResetDuration", 0], ["AddDuration", 1], ["AddStackOnly", 2]],
	],
	[
		"DurationTickTiming",
		CARRIER_DURATION_TICK_TIMING,
		LEGACY_DURATION_TICK_TIMING,
		[["Start", 0], ["End", 1]],
	],
	[
		"DurationExpirePolicy",
		CARRIER_DURATION_EXPIRE_POLICY,
		LEGACY_DURATION_EXPIRE_POLICY,
		[["FirstExpired", 0], ["AllExpired", 1]],
	],
	[
		"StatusHookPhase",
		CARRIER_STATUS_HOOK_PHASE,
		LEGACY_STATUS_HOOK_PHASE,
		[
			["BeforeAttributeChange", 0],
			["AfterAttributeChanged", 1],
			["ModifyOutgoingDamage", 2],
			["ModifyIncomingDamageBeforeMitigation", 3],
			["ModifyIncomingDamageAfterMitigation", 4],
			["ModifyDamageHitCount", 5],
			["ModifyDamageEffectSegmentDamage", 6],
			["BeforeHealthDamage", 7],
			["BeforeSkillExecution", 8],
			["AfterSkillExecution", 9],
			["GlobalTurnStart", 10],
			["OwnerTurnStart", 11],
			["GlobalTurnEnd", 12],
			["OwnerTurnEnd", 13],
			["RoundStart", 14],
			["RoundEnd", 15],
		],
	],
	[
		"CraftingFailureReason",
		CARRIER_CRAFTING_FAILURE_REASON,
		LEGACY_CRAFTING_FAILURE_REASON,
		[
			["None", 0],
			["InvalidRecipe", 1],
			["InvalidQuantity", 2],
			["MissingMaterials", 3],
			["NotEnoughSpace", 4],
		],
	],
	[
		"ShopFailureReason",
		CARRIER_SHOP_FAILURE_REASON,
		LEGACY_SHOP_FAILURE_REASON,
		[
			["None", 0],
			["InvalidItem", 1],
			["InvalidQuantity", 2],
			["NotEnoughGold", 3],
			["NotEnoughSpace", 4],
			["MissingItem", 5],
			["NotConfigured", 6],
		],
	],
	[
		"UpgradeKind",
		CARRIER_UPGRADE_KIND,
		LEGACY_UPGRADE_KIND,
		[["WarehouseCapacity", 0], ["CarrySlots", 1]],
	],
]

## 状态组件里的枚举整数镜像：[枚举名, 成员名, 取值, GDScript 常量名]。
const STATUS_COMPONENT_MIRRORS: Array = [
	["StatusChangeReason", "Applied", 0, "REASON_APPLIED"],
	["StatusChangeReason", "Removed", 1, "REASON_REMOVED"],
	["StatusChangeReason", "Refreshed", 2, "REASON_REFRESHED"],
	["StatusChangeReason", "StackChanged", 3, "REASON_STACK_CHANGED"],
	["StatusChangeReason", "DurationTicked", 4, "REASON_DURATION_TICKED"],
	["StatusChangeReason", "StackExpired", 5, "REASON_STACK_EXPIRED"],
	["StackPolicy", "ResetDuration", 0, "POLICY_RESET_DURATION"],
	["StackPolicy", "AddDuration", 1, "POLICY_ADD_DURATION"],
	["StackPolicy", "AddStackOnly", 2, "POLICY_ADD_STACK_ONLY"],
	["DurationTickTiming", "Start", 0, "TIMING_START"],
	["DurationTickTiming", "End", 1, "TIMING_END"],
	["StatusHookPhase", "BeforeAttributeChange", 0, "PHASE_BEFORE_ATTRIBUTE_CHANGE"],
	["StatusHookPhase", "AfterAttributeChanged", 1, "PHASE_AFTER_ATTRIBUTE_CHANGED"],
	["StatusHookPhase", "ModifyOutgoingDamage", 2, "PHASE_MODIFY_OUTGOING_DAMAGE"],
	["StatusHookPhase", "ModifyIncomingDamageBeforeMitigation", 3, "PHASE_MODIFY_INCOMING_DAMAGE_BEFORE_MITIGATION"],
	["StatusHookPhase", "ModifyIncomingDamageAfterMitigation", 4, "PHASE_MODIFY_INCOMING_DAMAGE_AFTER_MITIGATION"],
	["StatusHookPhase", "ModifyDamageHitCount", 5, "PHASE_MODIFY_DAMAGE_HIT_COUNT"],
	["StatusHookPhase", "ModifyDamageEffectSegmentDamage", 6, "PHASE_MODIFY_DAMAGE_EFFECT_SEGMENT_DAMAGE"],
	["StatusHookPhase", "BeforeHealthDamage", 7, "PHASE_BEFORE_HEALTH_DAMAGE"],
	["StatusHookPhase", "BeforeSkillExecution", 8, "PHASE_BEFORE_SKILL_EXECUTION"],
	["StatusHookPhase", "AfterSkillExecution", 9, "PHASE_AFTER_SKILL_EXECUTION"],
	["StatusHookPhase", "GlobalTurnStart", 10, "PHASE_GLOBAL_TURN_START"],
	["StatusHookPhase", "OwnerTurnStart", 11, "PHASE_OWNER_TURN_START"],
	["StatusHookPhase", "GlobalTurnEnd", 12, "PHASE_GLOBAL_TURN_END"],
	["StatusHookPhase", "OwnerTurnEnd", 13, "PHASE_OWNER_TURN_END"],
	["StatusHookPhase", "RoundStart", 14, "PHASE_ROUND_START"],
	["StatusHookPhase", "RoundEnd", 15, "PHASE_ROUND_END"],
]

## 状态实例里的过期策略镜像：[成员名, 取值, GDScript 常量名]。
const EXPIRE_POLICY_MIRRORS: Array = [
	["FirstExpired", 0, "EXPIRE_POLICY_FIRST_EXPIRED"],
	["AllExpired", 1, "EXPIRE_POLICY_ALL_EXPIRED"],
]

## SkillTargetingType 的代码生成边界：[成员名, 取值]。
const SKILL_TARGETING_MEMBERS: Array = [
	["Self", 0],
	["SingleEnemy", 1],
	["AllEnemies", 2],
	["AnySingleUnit", 3],
	["AllUnits", 4],
	["RandomEnemy", 5],
	["SpreadFromEnemy", 6],
]


## 返回 GodotAI 使用的稳定套件名称。
##
## @return 枚举族契约套件名。
func suite_name() -> String:
	return "enum_family_contract"


## 验证 8 个枚举载体的文件形状。
##
## @return 无返回值。
func test_carrier_shape() -> void:
	for row: Array in ENUM_ROWS:
		var carrier: String = str(row[1])
		assert_true(FileAccess.file_exists(carrier), "枚举载体必须存在：%s" % carrier)
		var text: String = FileAccess.get_file_as_string(carrier)
		assert_true(text.begins_with("extends RefCounted"), "枚举载体必须继承 RefCounted：%s" % carrier)
		assert_false(_declares_class_name(text), "枚举载体不得声明 class_name：%s" % carrier)
		assert_false(text.contains("TODO"), "枚举载体不得保留 TODO 占位：%s" % carrier)


## 验证每个枚举的成员顺序与取值在旧 C# 与 GDScript 载体间逐条一致。
##
## @return 无返回值。
func test_enum_values_match_legacy() -> void:
	for row: Array in ENUM_ROWS:
		var enum_name: String = str(row[0])
		var carrier: String = str(row[1])
		var legacy_path: String = str(row[2])
		var members: Array = row[3]

		var legacy: String = CS_OPTIONAL.read(legacy_path)
		if not legacy.is_empty():
			assert_true(FileAccess.file_exists(legacy_path), "旧 C# 枚举必须保留为兼容垫片：%s" % legacy_path)
		var carrier_text: String = FileAccess.get_file_as_string(carrier)

		var constants: Dictionary = load(carrier).get_script_constant_map()
		assert_true(constants.has(enum_name), "载体必须导出枚举：%s" % enum_name)
		var runtime_values: Dictionary = constants.get(enum_name)
		assert_eq(runtime_values.size(), members.size(), "%s 的成员数量必须一致。" % enum_name)

		_assert_legacy_members(legacy, enum_name, members)
		for member_row: Array in members:
			var member: String = str(member_row[0])
			var value: int = int(member_row[1])
			assert_true(
				carrier_text.contains("%s = %d," % [member, value]),
				"GDScript 载体必须保留成员与取值：%s.%s = %d" % [enum_name, member, value]
			)
			assert_eq(int(runtime_values.get(member)), value, "载体运行时取值必须正确：%s.%s" % [enum_name, member])


## 验证状态组件与状态实例里的枚举整数镜像与载体逐值一致。
##
## @return 无返回值。
func test_status_component_mirrors() -> void:
	var constants: Dictionary = load(STATUS_COMPONENT_GD).get_script_constant_map()
	var text: String = FileAccess.get_file_as_string(STATUS_COMPONENT_GD)
	for row: Array in STATUS_COMPONENT_MIRRORS:
		var enum_name: String = str(row[0])
		var member: String = str(row[1])
		var value: int = int(row[2])
		var const_name: String = str(row[3])
		assert_true(
			text.contains("const %s: int = %d" % [const_name, value]),
			"状态组件必须保留同值常量：%s（%s.%s）" % [const_name, enum_name, member]
		)
		assert_eq(int(constants.get(const_name, -1)), value, "状态组件运行时常量必须正确：%s" % const_name)

	var instance_constants: Dictionary = load(STATUS_EFFECT_INSTANCE_GD).get_script_constant_map()
	var instance_text: String = FileAccess.get_file_as_string(STATUS_EFFECT_INSTANCE_GD)
	for row: Array in EXPIRE_POLICY_MIRRORS:
		var value: int = int(row[1])
		var const_name: String = str(row[2])
		assert_true(
			instance_text.contains("const %s: int = %d" % [const_name, value]),
			"状态实例必须保留同值过期策略常量：%s" % const_name
		)
		assert_eq(int(instance_constants.get(const_name, -1)), value, "状态实例运行时常量必须正确：%s" % const_name)


## 验证合成与商店的失败原因枚举在旧 C# 与两份 GDScript 消费方间逐值一致。
##
## @return 无返回值。
func test_crafting_and_shop_failure_mirrors() -> void:
	_assert_enum_matches_consumer("CraftingFailureReason", CRAFTING_SERVICE_GD)
	_assert_enum_matches_consumer("CraftingFailureReason", CRAFTING_COMPONENT_GD)
	_assert_enum_matches_consumer("ShopFailureReason", SHOP_SERVICE_GD)


## 验证 SkillTargetingType 的代码生成边界：生成产物与旧 C# 枚举逐值一致且注明来源。
##
## @return 无返回值。
func test_skill_targeting_type_codegen_boundary() -> void:
	var legacy: String = CS_OPTIONAL.read(LEGACY_SKILL_TARGETING_TYPE)
	if not legacy.is_empty():
		assert_true(FileAccess.file_exists(LEGACY_SKILL_TARGETING_TYPE), "旧 C# 枚举必须保留为兼容垫片。")
	var generated_text: String = FileAccess.get_file_as_string(GENERATED_SKILL_TARGETING_TYPE_GD)
	var generated: Dictionary = load(GENERATED_SKILL_TARGETING_TYPE_GD).get_script_constant_map()
	assert_true(generated.has("Value"), "代码生成产物必须导出 Value 枚举。")
	var values: Dictionary = generated.get("Value")
	assert_eq(values.size(), SKILL_TARGETING_MEMBERS.size(), "生成枚举的成员数量必须与旧 C# 一致。")

	_assert_legacy_members(legacy, "SkillTargetingType", SKILL_TARGETING_MEMBERS)
	for member_row: Array in SKILL_TARGETING_MEMBERS:
		var member: String = str(member_row[0])
		var value: int = int(member_row[1])
		assert_true(generated_text.contains("%s = %d," % [member, value]), "生成产物必须保留取值：%s" % member)
		assert_eq(int(values.get(member)), value, "生成枚举运行时取值必须正确：%s" % member)

	var codegen: String = FileAccess.get_file_as_string(SKILL_TARGETING_CODEGEN_GD)
	if not legacy.is_empty():
		assert_true(
			codegen.contains("res://core/combat/skills/SkillTargetingType.cs"),
			"代码生成器必须继续以旧 C# 枚举为唯一来源。"
		)
	assert_true(
		codegen.contains("res://scripts/generated/SkillTargetingType.gd"),
		"代码生成器必须继续写入既有生成路径。"
	)
	for path: String in [CARD_MANAGER_GD, BATTLE_MANAGER_GD]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_true(
			text.contains("res://scripts/generated/SkillTargetingType.gd"),
			"战斗脚本必须继续引用生成产物：%s" % path
		)
		assert_true(text.contains("SKILL_TARGETING_TYPE.Value."), "战斗脚本必须继续按枚举名读取目标类型：%s" % path)


## 验证 UpgradeKind 在 GDScript 侧没有生产消费方，能力由具名方法暴露。
##
## @return 无返回值。
func test_upgrade_kind_has_no_gdscript_consumer() -> void:
	assert_eq(
		_grep_gd_references("res://core", "UpgradeKind"),
		[CARRIER_UPGRADE_KIND],
		"UpgradeKind 只允许命中自身载体。"
	)
	assert_eq(
		_grep_gd_references("res://core", "WarehouseCapacity = 0"),
		[CARRIER_UPGRADE_KIND],
		"升级项目整数只允许命中自身载体。"
	)
	var progression: String = FileAccess.get_file_as_string(PLAYER_PROGRESSION_GD)
	assert_true(progression.contains("func GetWarehouseCapacity()"), "进度脚本必须保留具名能力入口。")
	assert_true(progression.contains("func TryUpgradeCarrySlots()"), "进度脚本必须保留具名能力入口。")
	var shop_control_text: String = FileAccess.get_file_as_string(SHOP_CONTROL_GD)
	assert_true(shop_control_text.contains("ShopFailureReason"), "商店界面必须继续按失败原因整数映射文案。")


## 断言某个 GDScript 消费方脚本里的枚举与对应旧 C# 枚举逐值一致。
##
## @param enum_name 枚举名。
## @param consumer_path GDScript 消费方路径。
## @return 无返回值。
func _assert_enum_matches_consumer(enum_name: String, consumer_path: String) -> void:
	var legacy_path: String = ""
	for row: Array in ENUM_ROWS:
		if str(row[0]) == enum_name:
			legacy_path = str(row[2])
	assert_true(legacy_path != "", "契约表必须包含枚举：%s" % enum_name)
	assert_true(FileAccess.file_exists(consumer_path), "GDScript 消费方必须存在：%s" % consumer_path)

	var legacy: String = CS_OPTIONAL.read(legacy_path)
	var members: Array = _members_of(enum_name)
	_assert_legacy_members(legacy, enum_name, members)
	var constants: Dictionary = load(consumer_path).get_script_constant_map()
	assert_true(constants.has(enum_name), "消费方必须自带同值枚举：%s（%s）" % [enum_name, consumer_path])
	var values: Dictionary = constants.get(enum_name)

	for member_row: Array in members:
		var member: String = str(member_row[0])
		var value: int = int(member_row[1])
		assert_eq(int(values.get(member, -1)), value, "消费方运行时取值必须正确：%s.%s" % [enum_name, member])


## 取契约表中某个枚举的成员列表。
##
## @param enum_name 枚举名。
## @return [[成员名, 取值], …]；枚举不存在时返回空数组。
func _members_of(enum_name: String) -> Array:
	for row: Array in ENUM_ROWS:
		if str(row[0]) == enum_name:
			return row[3]
	return []


## 断言旧 C# 枚举的成员与取值序列与契约表完全一致。
##
## @param text C# 文件全文。
## @param enum_name 枚举名。
## @param expected [[成员名, 取值], …] 契约表。
## @return 无返回值。
func _assert_legacy_members(text: String, enum_name: String, expected: Array) -> void:
	# C# 垫片退役后没有对照源：整段退场；调用方自带的消费方断言仍照跑。
	if text.is_empty():
		return
	var parsed: Array = _parse_cs_enum(text, enum_name)
	assert_eq(parsed.size(), expected.size(), "旧 C# 枚举成员数量必须一致：%s" % enum_name)
	var shared: int = mini(parsed.size(), expected.size())
	for index: int in range(shared):
		var actual_row: Array = parsed[index]
		var expected_row: Array = expected[index]
		assert_eq(
			str(actual_row[0]),
			str(expected_row[0]),
			"旧 C# 枚举成员顺序必须保持：%s[%d]" % [enum_name, index]
		)
		assert_eq(
			int(actual_row[1]),
			int(expected_row[1]),
			"旧 C# 枚举取值必须保持：%s.%s" % [enum_name, str(expected_row[0])]
		)


## 解析旧 C# 枚举的成员与取值，支持隐式递增与显式赋值。
##
## @param text C# 文件全文。
## @param enum_name 枚举名。
## @return [[成员名, 取值], …]；找不到枚举声明时返回空数组。
func _parse_cs_enum(text: String, enum_name: String) -> Array:
	var rows: Array = []
	var started: bool = false
	var next_value: int = 0
	for raw_line: String in text.split("\n"):
		var line: String = raw_line.strip_edges()
		if not started:
			if line.contains("enum %s" % enum_name):
				started = true
			continue
		if line.begins_with("}"):
			break
		if line == "{":
			continue
		if line == "" or line.begins_with("//") or line.begins_with("*") or line.begins_with("/*"):
			continue
		var comment_index: int = line.find("//")
		if comment_index > 0:
			line = line.substr(0, comment_index).strip_edges()
		line = line.trim_suffix(",").strip_edges()
		var eq_index: int = line.find("=")
		if eq_index > 0:
			var explicit_value: int = int(line.substr(eq_index + 1).strip_edges())
			rows.append([line.substr(0, eq_index).strip_edges(), explicit_value])
			next_value = explicit_value + 1
			continue
		rows.append([line, next_value])
		next_value += 1
	return rows


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
## @return 命中文件的 res:// 路径数组（按目录遍历顺序）。
func _grep_gd_references(directory: String, needle: String) -> Array:
	var offenders: Array = []
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
