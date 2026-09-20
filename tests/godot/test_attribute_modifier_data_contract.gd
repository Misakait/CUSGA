@tool
extends McpTestSuite

## 属性修正条目（AttributeModifierData）生产迁移契约套件。
##
## 套件锁定三件事：两个生产资产改用 GDScript 修正条目脚本且序列化数值未变、
## 旧 C# 垫片仍然可加载（垫片退役后该断言经 CS_OPTIONAL 自动退场）、C# 消费者只依赖跨语言字段协议。
## 修正值真正生效的端到端链路由运行中的游戏经 game_eval 验证，因为编辑器里的
## C# Resource 只是占位实例，非 [Tool] 脚本无法在 test_run 里调用方法。

## 迁移期 C# 可选助手：C# 退役后 C# 对照断言自动退场，GDScript 侧断言照跑。
## 说明见 tests/godot/csharp_optional.gd。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## 本批 GDScript 属性修正条目脚本路径。
const MODIFIER_DATA_SCRIPT_PATH: String = "res://core/combat/status/attribute_modifier_data.gd"
## 旧 C# 属性修正条目兼容垫片路径。
const LEGACY_MODIFIER_DATA_PATH: String = "res://core/combat/status/AttributeModifierData.cs"
## 持有修正条目数组的状态数据脚本。
const MODIFIER_STATUS_DATA_PATH: String = "res://core/combat/buffs/AttributeModifierStatusData.cs"
## 消费修正条目的状态实例脚本。
const MODIFIER_STATUS_INSTANCE_PATH: String = "res://core/combat/buffs/AttributeModifierStatusInstance.cs"
## 修正条目字段协议脚本。
const PROTOCOL_PATH: String = "res://core/combat/status/AttributeModifierDataProtocol.cs"
## 力量效果资产（1 条物攻 +10 FlatAdd）。
const STRENGTH_RESOURCE_PATH: String = "res://resources/effects/strength.tres"
## 测试卡资产（1 条速度 +100 FlatAdd）。
const TEST_CARD_PATH: String = "res://resources/combat_skills/test_card_1.tres"
## AttributeType.PhysAtk 的枚举整数取值。
const ATTRIBUTE_TYPE_PHYS_ATK: int = 0
## AttributeType.Speed 的枚举整数取值。
const ATTRIBUTE_TYPE_SPEED: int = 4
## AttributeModifierMode.FlatAdd 的枚举整数取值。
const MODIFIER_MODE_FLAT_ADD: int = 0


## 返回 GodotAI 使用的稳定套件名称。
##
## @return 属性修正条目契约套件名。
func suite_name() -> String:
	return "attribute_modifier_data_contract"


## 验证两个生产资产改用 GDScript 修正条目，且旧 C# 垫片仍然存在可加载。
func test_production_assets_use_gdscript_modifier_data() -> void:
	for path: String in [STRENGTH_RESOURCE_PATH, TEST_CARD_PATH]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_true(
			text.contains(MODIFIER_DATA_SCRIPT_PATH),
			"%s 必须引用 GDScript 属性修正条目脚本。" % path
		)
		assert_false(
			text.contains("status/AttributeModifierData.cs"),
			"%s 不得继续引用旧 C# 属性修正条目脚本。" % path
		)
		assert_true(
			text.contains("Modifiers = Array[Resource]"),
			"%s 的修正条目数组必须改成通用 Resource 数组。" % path
		)

	# C# 对照部分：垫片退役后整段退场，上面的 GDScript 资产断言仍照跑。
	if CS_OPTIONAL.present(LEGACY_MODIFIER_DATA_PATH):
		assert_true(
			FileAccess.file_exists(LEGACY_MODIFIER_DATA_PATH),
			"旧 C# 属性修正条目必须作为兼容垫片保留。"
		)
		assert_true(
			load(LEGACY_MODIFIER_DATA_PATH) != null,
			"旧 C# 属性修正条目垫片必须仍然可以加载。"
		)


## 验证 GDScript 修正条目的字段默认值与旧 C# 实现逐项一致。
func test_gdscript_modifier_defaults_match_legacy() -> void:
	var script: Script = load(MODIFIER_DATA_SCRIPT_PATH)
	assert_true(script != null, "GDScript 属性修正条目脚本必须可以加载。")

	var instance: Resource = script.new()
	track(instance)
	assert_eq(int(instance.get("Type")), 0, "属性类型默认必须为旧 C# 首个枚举值物攻（0）。")
	assert_eq(int(instance.get("Mode")), MODIFIER_MODE_FLAT_ADD, "修正模式默认必须为 FlatAdd（0）。")
	assert_eq(float(instance.get("ValuePerStack")), 0.0, "每层修正值默认必须保持旧默认值 0。")

	## 只检查真正的声明行：中文注释里会提到 class_name，不能把注释误判成声明。
	var declares_global_name := false
	for line: String in FileAccess.get_file_as_string(MODIFIER_DATA_SCRIPT_PATH).split("\n"):
		if line.strip_edges().begins_with("class_name"):
			declares_global_name = true
	assert_false(
		declares_global_name,
		"属性修正条目脚本不得声明 class_name，避免与 C# 类型表冲突。"
	)


## 验证两个资产的序列化数值在切换脚本后没有丢失。
func test_serialized_values_preserved_in_assets() -> void:
	var strength: Resource = load(STRENGTH_RESOURCE_PATH)
	assert_true(strength != null, "必须能加载 strength.tres。")
	var strength_status: Resource = strength.get("Status")
	assert_true(strength_status != null, "strength.tres 必须带有状态数据子资源。")
	assert_eq(
		String(strength_status.get("Id")),
		"strength_up",
		"strength.tres 的状态 Id 必须保持 strength_up。"
	)
	var strength_modifiers: Array = strength_status.get("Modifiers")
	assert_eq(strength_modifiers.size(), 1, "strength.tres 必须保留 1 条修正条目。")
	assert_eq(
		String(strength_modifiers[0].get_script().resource_path),
		MODIFIER_DATA_SCRIPT_PATH,
		"strength.tres 的修正条目必须是本批 GDScript 实现。"
	)
	assert_eq(
		int(strength_modifiers[0].get("Type")),
		ATTRIBUTE_TYPE_PHYS_ATK,
		"strength.tres 的属性类型必须保持物攻（0）。"
	)
	assert_eq(
		int(strength_modifiers[0].get("Mode")),
		MODIFIER_MODE_FLAT_ADD,
		"strength.tres 的修正模式必须保持 FlatAdd（0）。"
	)
	assert_eq(
		float(strength_modifiers[0].get("ValuePerStack")),
		10.0,
		"strength.tres 的每层修正值必须保持 10。"
	)

	var card: Resource = load(TEST_CARD_PATH)
	assert_true(card != null, "必须能加载 test_card_1.tres。")
	var card_status: Resource = _find_status_effect(card)
	assert_true(card_status != null, "test_card_1.tres 必须带有状态效果子资源。")
	assert_eq(int(card_status.get("MaxStacks")), 999, "test_card_1.tres 的最大层数必须保持 999。")
	assert_eq(int(card_status.get("Policy")), 2, "test_card_1.tres 的叠加策略必须保持 2。")
	var card_modifiers: Array = card_status.get("Modifiers")
	assert_eq(card_modifiers.size(), 1, "test_card_1.tres 必须保留 1 条修正条目。")
	assert_eq(
		String(card_modifiers[0].get_script().resource_path),
		MODIFIER_DATA_SCRIPT_PATH,
		"test_card_1.tres 的修正条目必须是本批 GDScript 实现。"
	)
	assert_eq(
		int(card_modifiers[0].get("Type")),
		ATTRIBUTE_TYPE_SPEED,
		"test_card_1.tres 的属性类型必须保持速度（4）。"
	)
	assert_eq(
		float(card_modifiers[0].get("ValuePerStack")),
		100.0,
		"test_card_1.tres 的每层修正值必须保持 100。"
	)


## 验证 C# 消费者只依赖跨语言字段协议，且回滚分支仍然存在。
func test_csharp_consumers_use_field_protocol() -> void:
	if not CS_OPTIONAL.present_all(
		[MODIFIER_STATUS_DATA_PATH, MODIFIER_STATUS_INSTANCE_PATH, PROTOCOL_PATH]
	):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var status_data_source: String = FileAccess.get_file_as_string(MODIFIER_STATUS_DATA_PATH)
	assert_false(
		status_data_source.contains("Array<AttributeModifierData>"),
		"状态数据不得再声明强类型 Array<AttributeModifierData>，否则 GDScript 条目无法加载。"
	)
	assert_true(
		status_data_source.contains("[Export] public Array Modifiers"),
		"状态数据的修正条目必须改成通用数组。"
	)

	var instance_source: String = FileAccess.get_file_as_string(MODIFIER_STATUS_INSTANCE_PATH)
	assert_true(
		instance_source.contains("AttributeModifierDataProtocol.TryRead"),
		"状态实例必须经字段协议读取修正条目。"
	)
	assert_false(
		instance_source.contains("modifier.Type"),
		"状态实例不得再直接访问旧 C# 强类型属性。"
	)

	var protocol_source: String = FileAccess.get_file_as_string(PROTOCOL_PATH)
	assert_true(
		protocol_source.contains("is AttributeModifierData legacy"),
		"字段协议必须保留旧 C# 垫片分支，保证回滚可用。"
	)
	assert_true(
		protocol_source.contains("resource.Get(\"ValuePerStack\")"),
		"字段协议必须提供 GDScript 同名字段分支。"
	)


## 验证按 C# 字段协议使用的字段名读取真实资产条目时，能得到与旧 C# 完全一致的元组值。
##
## 编辑器里的 C# Resource 是占位实例（非 [Tool] 脚本不能调用方法），所以这里只验证
## 字段通道；真正让修正值生效的端到端链路由运行中的游戏经 game_eval 验证。
func test_asset_entries_read_through_field_protocol() -> void:
	var cases: Array[Dictionary] = [
		{
			"path": STRENGTH_RESOURCE_PATH,
			"type": ATTRIBUTE_TYPE_PHYS_ATK,
			"value": 10.0,
		},
		{
			"path": TEST_CARD_PATH,
			"type": ATTRIBUTE_TYPE_SPEED,
			"value": 100.0,
		},
	]
	for case: Dictionary in cases:
		var entry: Resource = _first_modifier(case["path"])
		assert_true(entry != null, "%s 必须能取出修正条目。" % case["path"])
		assert_eq(
			String(entry.get_script().resource_path),
			MODIFIER_DATA_SCRIPT_PATH,
			"%s 的条目必须是 GDScript 生产实现。" % case["path"]
		)
		assert_eq(int(entry.get("Type")), case["type"], "%s 的属性类型必须保持。" % case["path"])
		assert_eq(int(entry.get("Mode")), MODIFIER_MODE_FLAT_ADD, "%s 的修正模式必须保持。" % case["path"])
		assert_eq(
			float(entry.get("ValuePerStack")),
			case["value"],
			"%s 的每层修正值必须保持。" % case["path"]
		)


## 取出资产里第一条属性修正条目。
##
## @param path 资产路径，支持力量效果（直接带 Status）与战斗技能（Effects 内带 Status）。
## @return 第一条修正条目；资产或条目缺失时返回 null。
func _first_modifier(path: String) -> Resource:
	var resource: Resource = load(path)
	if resource == null:
		return null
	var status: Resource = resource.get("Status") as Resource
	if status == null:
		status = _find_status_effect(resource)
	if status == null:
		return null
	var modifiers: Array = status.get("Modifiers")
	if modifiers.is_empty():
		return null
	return modifiers[0]


## 从卡片效果数组里取出第一个带状态数据的效果。
##
## @param card 战斗技能资源。
## @return 找到的状态数据资源；没有时返回 null。
func _find_status_effect(card: Resource) -> Resource:
	var effects: Array = card.get("Effects")
	for effect: Variant in effects:
		var status: Variant = effect.get("Status")
		if status != null:
			return status
	return null
