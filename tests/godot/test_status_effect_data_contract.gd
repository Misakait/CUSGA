@tool
extends McpTestSuite

## 状态数据族（StatusEffectData 基类 + 9 个数据子类）生产迁移契约套件。
##
## 套件锁定四件事：状态数据改用 GDScript 生产实现、基类默认值与旧 C# 逐字一致、
## 资产序列化数值未变、GDScript 状态实例可以由同一份数据构造并读到相同字段。
## 运行时“真的能挂上状态并结算伤害”由运行中的游戏经 game_eval 验证。
## 套件同时锁定旧 C# 垫片与跨语言协议；垫片退役后该部分经 CS_OPTIONAL 自动退场
## （见 tests/godot/csharp_optional.gd），GDScript 侧断言照跑。

## 本批 GDScript 生产脚本路径。
const BASE_SCRIPT_PATH: String = "res://core/combat/status/status_effect_data.gd"
const ATTRIBUTE_MODIFIER_STATUS_PATH: String = \
	"res://core/combat/buffs/attribute_modifier_status_data.gd"
const SHIELD_STATUS_PATH: String = "res://core/combat/buffs/shield_status_data.gd"
const BURN_STATUS_PATH: String = "res://core/combat/buffs/burn_status_data.gd"
const ATTRIBUTE_CHANGE_TRIGGER_PATH: String = \
	"res://core/combat/status/attribute_change_trigger_status_data.gd"

## 后续批次补齐的 5 组状态数据生产脚本（属性变化拦截、Boss 扣血上限、段数修正、
## 每段基础伤害修正、脆弱）与它们对应的 GDScript 生产实例脚本。
const ATTRIBUTE_CHANGE_GUARD_STATUS_PATH: String = \
	"res://core/combat/status/attribute_change_guard_status_data.gd"
const BOSS_DAMAGE_CAP_STATUS_PATH: String = \
	"res://core/combat/buffs/boss_damage_cap_status_data.gd"
const HIT_COUNT_MODIFIER_STATUS_PATH: String = \
	"res://core/combat/buffs/hit_count_modifier_status_data.gd"
const NEXT_ATTACK_DAMAGE_BONUS_STATUS_PATH: String = \
	"res://core/combat/buffs/next_attack_damage_bonus_status_data.gd"
const VULNERABLE_STATUS_PATH: String = \
	"res://core/combat/buffs/vulnerable_status_data.gd"

const ATTRIBUTE_CHANGE_GUARD_INSTANCE_PATH: String = \
	"res://core/combat/status/attribute_change_guard_status_instance.gd"
const BOSS_DAMAGE_CAP_INSTANCE_PATH: String = \
	"res://core/combat/buffs/boss_damage_cap_status_instance.gd"
const HIT_COUNT_MODIFIER_INSTANCE_PATH: String = \
	"res://core/combat/buffs/hit_count_modifier_status_instance.gd"
const NEXT_ATTACK_DAMAGE_BONUS_INSTANCE_PATH: String = \
	"res://core/combat/buffs/next_attack_damage_bonus_status_instance.gd"
const VULNERABLE_INSTANCE_PATH: String = \
	"res://core/combat/buffs/vulnerable_status_instance.gd"

## 旧 C# 兼容垫片路径。
const LEGACY_STATUS_DATA_PATH: String = "res://core/combat/status/StatusEffectData.cs"
const LEGACY_ATTRIBUTE_MODIFIER_STATUS_PATH: String = \
	"res://core/combat/buffs/AttributeModifierStatusData.cs"
const LEGACY_SHIELD_STATUS_PATH: String = "res://core/combat/buffs/ShieldStatusData.cs"
const LEGACY_BURN_STATUS_PATH: String = "res://core/combat/buffs/BurnStatusData.cs"
const LEGACY_TRIGGER_STATUS_PATH: String = \
	"res://core/combat/status/AttributeChangeTriggerStatusData.cs"

## GDScript 状态实例生产路径与跨语言字段协议路径。
const INSTANCE_BASE_PATH: String = "res://core/combat/status/status_effect_instance.gd"
const ATTRIBUTE_MODIFIER_INSTANCE_PATH: String = \
	"res://core/combat/buffs/attribute_modifier_status_instance.gd"
const SHIELD_INSTANCE_PATH: String = "res://core/combat/buffs/shield_status_instance.gd"
const BURN_INSTANCE_PATH: String = "res://core/combat/buffs/burn_status_instance.gd"
const TRIGGER_INSTANCE_PATH: String = \
	"res://core/combat/status/attribute_change_trigger_status_instance.gd"
const PROTOCOL_PATH: String = "res://core/combat/status/StatusEffectDataProtocol.cs"

## 迁移期 C# 可选助手：C# 退役后 C# 对照断言自动退场，GDScript 侧断言照跑。
## 说明见 tests/godot/csharp_optional.gd。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## 状态变化载体（上下文与事件）的 GDScript 生产路径。
const STATUS_CHANGE_CONTEXT_PATH: String = \
	"res://core/combat/status/status_change_context.gd"
const STATUS_CHANGED_EVENT_PATH: String = \
	"res://core/combat/status/status_changed_event.gd"

## 旧 C# 状态实例与状态变化载体垫片路径；全部保留到全量迁移完成。
const LEGACY_INSTANCE_SHIM_PATHS: Array[String] = [
	"res://core/combat/status/StatusEffectInstance.cs",
	"res://core/combat/status/StatusChangeContext.cs",
	"res://core/combat/status/StatusChangedEvent.cs",
	"res://core/combat/buffs/AttributeModifierStatusInstance.cs",
	"res://core/combat/buffs/ShieldStatusInstance.cs",
	"res://core/combat/buffs/BurnStatusInstance.cs",
	"res://core/combat/status/AttributeChangeTriggerStatusInstance.cs",
	"res://core/combat/status/AttributeChangeGuardStatusInstance.cs",
	"res://core/combat/buffs/BossDamageCapStatusInstance.cs",
	"res://core/combat/buffs/HitCountModifierStatusInstance.cs",
	"res://core/combat/buffs/NextAttackDamageBonusStatusInstance.cs",
	"res://core/combat/buffs/VulnerableStatusInstance.cs",
]

## 本批切换引用的资产路径。
const STRENGTH_ASSET_PATH: String = "res://resources/effects/strength.tres"
const TEST_CARD_1_PATH: String = "res://resources/combat_skills/test_card_1.tres"
const TEST_CARD_2_PATH: String = "res://resources/combat_skills/test_card_2.tres"
const BMOB_PATH: String = "res://resources/combat_skills/bmob.tres"
const TRIGGER_ASSET_PATH: String = "res://resources/buffs/draw_when_physAtk_decreased.tres"

## 任何资产都不应再引用的旧 C# 状态数据脚本标记。
const LEGACY_ASSET_MARKERS: Array[String] = [
	"AttributeModifierStatusData.cs",
	"ShieldStatusData.cs",
	"BurnStatusData.cs",
	"AttributeChangeTriggerStatusData.cs",
]


## 返回 GodotAI 使用的稳定套件名称。
##
## @return 状态数据契约套件名。
func suite_name() -> String:
	return "status_effect_data_contract"


## 验证生产脚本存在且继承关系与迁移设计一致。
func test_production_scripts_exist_and_inherit() -> void:
	for path: String in [
		BASE_SCRIPT_PATH,
		ATTRIBUTE_MODIFIER_STATUS_PATH,
		SHIELD_STATUS_PATH,
		BURN_STATUS_PATH,
		ATTRIBUTE_CHANGE_TRIGGER_PATH,
	]:
		assert_true(FileAccess.file_exists(path), "生产脚本必须存在：%s" % path)

	var base_text: String = FileAccess.get_file_as_string(BASE_SCRIPT_PATH)
	assert_true(base_text.contains("extends Resource"), "状态数据基类必须直接继承 Resource。")
	for field: String in [
		"@export var Id: StringName",
		"@export var DisplayName: String",
		"@export var Description: String",
		"@export var Icon: Texture2D",
		"@export var MaxStacks: int = 1",
		"@export var Policy: int = 0",
		"@export var ExpirePolicy: int = 0",
		"@export var DurationTickTiming: int = 0",
		"@export var DefaultHookPriority: int = 0",
		"@export var InitOwnerTurnDuration: int = 0",
		"@export var InitGlobalTurnDuration: int = 0",
		"@export var InitRoundDuration: int = 0",
	]:
		assert_true(base_text.contains(field), "状态数据基类必须声明字段：%s" % field)

	for path: String in [
		ATTRIBUTE_MODIFIER_STATUS_PATH,
		SHIELD_STATUS_PATH,
		BURN_STATUS_PATH,
		ATTRIBUTE_CHANGE_TRIGGER_PATH,
	]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_true(
			text.contains('extends "%s"' % BASE_SCRIPT_PATH),
			"状态数据子类必须继承 GDScript 基类：%s" % path
		)
		assert_true(
			text.contains("func CreateInstance("),
			"状态数据子类必须实现 CreateInstance：%s" % path
		)


## 验证基类默认值同旧 C# 字段默认值一致。
func test_base_defaults_match_legacy_fields() -> void:
	var data: Resource = load(BASE_SCRIPT_PATH).new()
	track(data)
	assert_eq(str(data.get("Id")), "", "状态 Id 默认值必须与旧 C# 一致。")
	assert_eq(str(data.get("DisplayName")), "", "显示名称默认值必须与旧 C# 一致。")
	assert_eq(str(data.get("Description")), "", "描述默认值必须与旧 C# 一致。")
	assert_true(data.get("Icon") == null, "图标默认值必须与旧 C# 一致（未配置）。")
	assert_eq(int(data.get("MaxStacks")), 1, "最大层数默认值必须与旧 C# 一致。")
	assert_eq(int(data.get("Policy")), 0, "叠加策略默认值必须是 ResetDuration。")
	assert_eq(int(data.get("ExpirePolicy")), 0, "过期策略默认值必须是 FirstExpired。")
	assert_eq(int(data.get("DurationTickTiming")), 0, "扣减时机默认值必须是 Start。")
	assert_eq(int(data.get("DefaultHookPriority")), 0, "默认优先级必须与旧 C# 一致。")
	assert_eq(int(data.get("InitOwnerTurnDuration")), 0, "自身回合持续时间默认值必须为 0。")
	assert_eq(int(data.get("InitGlobalTurnDuration")), 0, "全场回合持续时间默认值必须为 0。")
	assert_eq(int(data.get("InitRoundDuration")), 0, "轮次持续时间默认值必须为 0。")


## 验证子类默认值同旧 C# 字段默认值一致。
func test_subclass_defaults_match_legacy_fields() -> void:
	var shield: Resource = load(SHIELD_STATUS_PATH).new()
	track(shield)
	assert_eq(float(shield.get("DefaultShieldAmount")), 0.0, "护盾默认值必须与旧 C# 一致。")

	var burn: Resource = load(BURN_STATUS_PATH).new()
	track(burn)
	assert_eq(float(burn.get("DamagePerStack")), 5.0, "灼烧每层伤害默认值必须与旧 C# 一致。")
	assert_eq(int(burn.get("DamageType")), 1, "灼烧伤害类型默认值必须是 Magic。")
	assert_eq(int(burn.get("Element")), 5, "灼烧五行默认值必须是 Fire。")
	assert_eq(int(burn.get("DamageModifiers")), 0, "灼烧伤害修饰默认值必须是 None。")

	var trigger: Resource = load(ATTRIBUTE_CHANGE_TRIGGER_PATH).new()
	track(trigger)
	assert_eq(int(trigger.get("TargetAttribute")), 0, "触发目标属性默认值必须与旧 C# 一致。")
	assert_eq(int(trigger.get("Direction")), 0, "触发方向默认值必须是 Any。")
	assert_eq((trigger.get("Effects") as Array).size(), 0, "触发效果默认必须是空数组。")

	var modifier: Resource = load(ATTRIBUTE_MODIFIER_STATUS_PATH).new()
	track(modifier)
	assert_eq((modifier.get("Modifiers") as Array).size(), 0, "修正条目默认必须是空数组。")


## 验证 GDScript 状态实例可以接受状态数据并读到同一份字段。
##
## 这一步是本批的跨语言关键：数据与实例都在 GDScript，但字段名/默认值仍与旧 C# 逐字一致，
## 因此旧 C# 垫片与 GDScript 生产实现可以被同一套字段协议读取。
func test_gdscript_instances_accept_status_data() -> void:
	var source := Node.new()
	var owner := Node.new()
	track(source)
	track(owner)

	var modifier_data: Resource = load(ATTRIBUTE_MODIFIER_STATUS_PATH).new()
	track(modifier_data)
	modifier_data.set("Id", &"modifier_probe")
	modifier_data.set("MaxStacks", 3)
	modifier_data.set("Policy", 1)
	var modifier_instance: Variant = modifier_data.call("CreateInstance", source, owner)
	track(modifier_instance)
	assert_true(modifier_instance != null, "GDScript 状态数据必须能创建 GDScript 状态实例。")
	if modifier_instance != null:
		assert_eq(
			str(modifier_instance.get_script().resource_path),
			ATTRIBUTE_MODIFIER_INSTANCE_PATH,
			"属性修正状态必须创建对应的 GDScript 实例。"
		)
		assert_true(
			modifier_instance.get("Data") == modifier_data,
			"实例必须持有同一份 GDScript 状态数据。"
		)
		assert_eq(str(modifier_instance.get("Id")), "modifier_probe", "实例必须读到 GDScript Id。")
		assert_eq(int(modifier_instance.get("MaxStacks")), 3, "实例必须读到 GDScript 最大层数。")
		assert_eq(int(modifier_instance.get("Policy")), 1, "实例必须读到 GDScript 叠加策略。")

	var shield_data: Resource = load(SHIELD_STATUS_PATH).new()
	track(shield_data)
	shield_data.set("Id", &"shield_probe")
	shield_data.set("DefaultShieldAmount", 20.0)
	shield_data.set("InitOwnerTurnDuration", 2)
	var shield_instance: Variant = shield_data.call("CreateInstance", source, owner)
	track(shield_instance)
	assert_true(shield_instance != null, "GDScript 护盾状态数据必须能创建 GDScript 实例。")
	if shield_instance != null:
		assert_eq(
			str(shield_instance.get_script().resource_path),
			SHIELD_INSTANCE_PATH,
			"护盾状态必须创建对应的 GDScript 实例。"
		)
		assert_eq(int(shield_instance.get("ShieldAmount")), 20, "护盾量必须来自 GDScript 数据。")
		assert_eq(int(shield_instance.get("OwnerTurnDuration")), 2, "持续时间必须来自 GDScript 数据。")

	var trigger_data: Resource = load(ATTRIBUTE_CHANGE_TRIGGER_PATH).new()
	track(trigger_data)
	trigger_data.set("Id", &"trigger_probe")
	var trigger_instance: Variant = trigger_data.call("CreateInstance", source, owner)
	track(trigger_instance)
	assert_true(trigger_instance != null, "GDScript 触发状态数据必须能创建 GDScript 实例。")
	if trigger_instance != null:
		assert_eq(
			str(trigger_instance.get_script().resource_path),
			TRIGGER_INSTANCE_PATH,
			"触发状态必须创建对应的 GDScript 实例。"
		)

	var burn_data: Resource = load(BURN_STATUS_PATH).new()
	track(burn_data)
	burn_data.set("Id", &"burn_probe")
	burn_data.set("DamagePerStack", 7.0)
	var burn_instance: Variant = burn_data.call("CreateInstance", source, owner)
	track(burn_instance)
	assert_true(burn_instance != null, "GDScript 灼烧状态数据必须能创建 GDScript 实例。")
	if burn_instance != null:
		assert_eq(
			str(burn_instance.get_script().resource_path),
			BURN_INSTANCE_PATH,
			"灼烧状态必须创建对应的 GDScript 实例。"
		)
		assert_eq(str(burn_instance.get("Id")), "burn_probe", "灼烧实例必须读到 GDScript Id。")


## 验证 5 个资产已经切换到 GDScript 状态数据。
func test_assets_switched_to_gdscript() -> void:
	var expectations: Dictionary = {
		STRENGTH_ASSET_PATH: ATTRIBUTE_MODIFIER_STATUS_PATH,
		TEST_CARD_1_PATH: ATTRIBUTE_MODIFIER_STATUS_PATH,
		TEST_CARD_2_PATH: SHIELD_STATUS_PATH,
		BMOB_PATH: BURN_STATUS_PATH,
		TRIGGER_ASSET_PATH: ATTRIBUTE_CHANGE_TRIGGER_PATH,
	}
	for asset_path: String in expectations.keys():
		var text: String = FileAccess.get_file_as_string(asset_path)
		assert_true(
			text.contains(expectations[asset_path]),
			"资产必须引用 GDScript 状态数据：%s" % asset_path
		)
		for marker: String in LEGACY_ASSET_MARKERS:
			assert_false(
				text.contains(marker),
				"资产不得继续引用旧 C# 状态数据：%s -> %s" % [asset_path, marker]
			)


## 验证代表性资产的序列化字段与值未变。
func test_serialized_asset_values_preserved() -> void:
	var modifier_status: Resource = load(STRENGTH_ASSET_PATH).get("Status")
	assert_true(modifier_status != null, "力量效果必须保留状态子资源。")
	if modifier_status != null:
		assert_eq(
			str(modifier_status.get_script().resource_path),
			ATTRIBUTE_MODIFIER_STATUS_PATH,
			"力量状态必须使用 GDScript 状态数据。"
		)
		assert_eq(str(modifier_status.get("Id")), "strength_up", "力量状态 Id 不得丢失。")
		var modifiers: Array = modifier_status.get("Modifiers")
		assert_eq(modifiers.size(), 1, "力量状态必须保留一条修正条目。")
		assert_eq(
			str(modifiers[0].get_script().resource_path),
			"res://core/combat/status/attribute_modifier_data.gd",
			"修正条目必须仍是 GDScript 生产实现。"
		)
		assert_eq(float(modifiers[0].get("ValuePerStack")), 10.0, "修正数值不得丢失。")

	var card_one: Resource = load(TEST_CARD_1_PATH)
	var card_one_effects: Array = card_one.get("Effects")
	assert_eq(card_one_effects.size(), 2, "测试卡1 必须保留两个效果。")
	var card_one_status: Resource = card_one_effects[1].get("Status")
	assert_eq(
		str(card_one_status.get_script().resource_path),
		ATTRIBUTE_MODIFIER_STATUS_PATH,
		"测试卡1 的状态必须使用 GDScript 状态数据。"
	)
	assert_eq(int(card_one_status.get("MaxStacks")), 999, "测试卡1 最大层数不得改变。")
	assert_eq(int(card_one_status.get("Policy")), 2, "测试卡1 叠加策略不得改变。")
	var card_one_modifiers: Array = card_one_status.get("Modifiers")
	assert_eq(int(card_one_modifiers[0].get("Type")), 4, "修正类型不得改变。")
	assert_eq(float(card_one_modifiers[0].get("ValuePerStack")), 100.0, "修正数值不得改变。")

	var card_two: Resource = load(TEST_CARD_2_PATH)
	var card_two_effects: Array = card_two.get("Effects")
	assert_eq(card_two_effects.size(), 2, "测试卡2 必须保留两个效果。")
	var shield_status: Resource = card_two_effects[1].get("ShieldStatus")
	assert_eq(
		str(shield_status.get_script().resource_path),
		SHIELD_STATUS_PATH,
		"测试卡2 的护盾必须使用 GDScript 状态数据。"
	)
	assert_eq(float(shield_status.get("DefaultShieldAmount")), 20.0, "护盾数值不得改变。")
	assert_eq(str(shield_status.get("DisplayName")), "护盾", "护盾显示名称不得改变。")

	var bmob: Resource = load(BMOB_PATH)
	var bmob_effects: Array = bmob.get("Effects")
	assert_eq(bmob_effects.size(), 2, "炸弹技能必须保留两个效果。")
	var burn_status: Resource = bmob_effects[1].get("Status")
	assert_eq(
		str(burn_status.get_script().resource_path),
		BURN_STATUS_PATH,
		"炸弹技能的灼烧必须使用 GDScript 状态数据。"
	)
	assert_eq(str(burn_status.get("Id")), "bomb_burn", "灼烧 Id 不得丢失。")
	assert_eq(str(burn_status.get("DisplayName")), "灼烧", "灼烧显示名称不得丢失。")
	assert_eq(int(burn_status.get("MaxStacks")), 3, "灼烧最大层数不得改变。")
	assert_eq(int(burn_status.get("InitOwnerTurnDuration")), 5, "灼烧持续时间不得改变。")

	var trigger: Resource = load(TRIGGER_ASSET_PATH)
	assert_eq(
		str(trigger.get_script().resource_path),
		ATTRIBUTE_CHANGE_TRIGGER_PATH,
		"触发 buff 资产必须使用 GDScript 状态数据。"
	)
	assert_eq(str(trigger.get("Id")), "Draw_When_PhysAtk_Decreased", "触发 buff Id 不得丢失。")
	assert_eq(int(trigger.get("Direction")), 2, "触发方向不得改变。")


## 验证旧 C# 垫片、GDScript 生产实例与跨语言协议同时保留。
func test_legacy_shims_and_protocol_kept() -> void:
	if not CS_OPTIONAL.present_all(LEGACY_INSTANCE_SHIM_PATHS + [PROTOCOL_PATH]):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	for path: String in [
		LEGACY_STATUS_DATA_PATH,
		LEGACY_ATTRIBUTE_MODIFIER_STATUS_PATH,
		LEGACY_SHIELD_STATUS_PATH,
		LEGACY_BURN_STATUS_PATH,
		LEGACY_TRIGGER_STATUS_PATH,
		PROTOCOL_PATH,
	]:
		assert_true(FileAccess.file_exists(path), "兼容垫片与协议必须保留：%s" % path)

	# 状态实例与状态变化载体已迁到 GDScript 生产实现，旧 C# 本体仍逐文件保留。
	for path: String in LEGACY_INSTANCE_SHIM_PATHS:
		assert_true(FileAccess.file_exists(path), "旧 C# 状态实例垫片必须保留：%s" % path)


## 验证状态实例族（基类 + 9 个实例子类 + 2 个状态变化载体）已有 GDScript 生产实现。
##
## @return 无返回值。
func test_instance_family_production_scripts_exist() -> void:
	for path: String in [
		INSTANCE_BASE_PATH,
		ATTRIBUTE_MODIFIER_INSTANCE_PATH,
		SHIELD_INSTANCE_PATH,
		BURN_INSTANCE_PATH,
		TRIGGER_INSTANCE_PATH,
		ATTRIBUTE_CHANGE_GUARD_INSTANCE_PATH,
		BOSS_DAMAGE_CAP_INSTANCE_PATH,
		HIT_COUNT_MODIFIER_INSTANCE_PATH,
		NEXT_ATTACK_DAMAGE_BONUS_INSTANCE_PATH,
		VULNERABLE_INSTANCE_PATH,
		STATUS_CHANGE_CONTEXT_PATH,
		STATUS_CHANGED_EVENT_PATH,
	]:
		assert_true(FileAccess.file_exists(path), "状态实例生产脚本必须存在：%s" % path)

	var base_text: String = FileAccess.get_file_as_string(INSTANCE_BASE_PATH)
	assert_true(
		base_text.contains('extends RefCounted'),
		"状态实例基类必须直接继承 RefCounted，才能被数据脚本按脚本路径实例化。"
	)
	for method_name: String in [
		"IsExpired",
		"TryIncreaseStack",
		"TryRemoveStack",
		"ResetDurations",
		"AddDurationsFrom",
		"GetHookPriority",
		"GetAttributeModifiersData",
		"ConsumeMarkedSkillExecutionUse",
		"ApplyModifyDamageHitCount",
		"ApplyModifyDamageEffectSegmentDamage",
		"ApplyModifyOutgoingDamage",
		"ApplyModifyIncomingDamageBeforeMitigation",
		"ApplyModifyIncomingDamageAfterMitigation",
		"ApplyBeforeHealthDamage",
	]:
		assert_true(
			base_text.contains("func %s(" % method_name),
			"状态实例基类必须提供旧 C# 同名协议方法：%s" % method_name
		)


## 验证状态实例生产脚本逐条继承 GDScript 基类，且旧 C# 垫片保留同样的字段协议边界。
func test_instance_production_scripts_inherit_gdscript_base() -> void:
	var base_extends: String = 'extends "%s"' % INSTANCE_BASE_PATH
	for path: String in [
		ATTRIBUTE_MODIFIER_INSTANCE_PATH,
		SHIELD_INSTANCE_PATH,
		BURN_INSTANCE_PATH,
		TRIGGER_INSTANCE_PATH,
		ATTRIBUTE_CHANGE_GUARD_INSTANCE_PATH,
		BOSS_DAMAGE_CAP_INSTANCE_PATH,
		HIT_COUNT_MODIFIER_INSTANCE_PATH,
		NEXT_ATTACK_DAMAGE_BONUS_INSTANCE_PATH,
		VULNERABLE_INSTANCE_PATH,
	]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_true(text.contains(base_extends), "状态实例必须继承 GDScript 基类：%s" % path)

	# 旧 C# 实例垫片必须继续保持“数据容器降级为通用 Resource”，回滚时才不需要改调用点。
	for path: String in LEGACY_INSTANCE_SHIM_PATHS:
		if not CS_OPTIONAL.present(path):
			continue
		var text: String = FileAccess.get_file_as_string(path)
		if not text.contains("StatusEffectInstance(data, source, owner)"):
			continue
		assert_true(
			text.contains("Resource data,"),
			"旧 C# 状态实例构造参数必须保持通用 Resource：%s" % path
		)

	# C# 协议对照：垫片退役后整段退场，上面的 GDScript 断言仍照跑。
	var protocol_source: String = CS_OPTIONAL.read(PROTOCOL_PATH)
	if not protocol_source.is_empty():
		assert_true(
			protocol_source.contains("status_effect_data.gd"),
			"字段协议必须识别 GDScript 状态数据基类。"
		)
		assert_true(
			protocol_source.contains("GetBaseScript"),
			"字段协议必须沿基类脚本链识别子类，因为子类脚本路径指向自身。"
		)


## 验证后续补齐的 5 组状态数据也有 GDScript 生产实现，且 GDScript 实例可按字段协议消费。
##
## 这 5 组（属性变化拦截、Boss 单次扣血上限、段数修正、每段基础伤害修正、脆弱）此前没有任何
## 资产引用，因此本批连同实例族一起切到 GDScript 生产实现，旧 C# 数据与实例全部保留为兼容垫片。
##
## @return 无返回值。
func test_remaining_status_data_family_production() -> void:
	var base_extends: String = 'extends "%s"' % BASE_SCRIPT_PATH
	var expectations: Dictionary = {
		ATTRIBUTE_CHANGE_GUARD_STATUS_PATH: ATTRIBUTE_CHANGE_GUARD_INSTANCE_PATH,
		BOSS_DAMAGE_CAP_STATUS_PATH: BOSS_DAMAGE_CAP_INSTANCE_PATH,
		HIT_COUNT_MODIFIER_STATUS_PATH: HIT_COUNT_MODIFIER_INSTANCE_PATH,
		NEXT_ATTACK_DAMAGE_BONUS_STATUS_PATH: NEXT_ATTACK_DAMAGE_BONUS_INSTANCE_PATH,
		VULNERABLE_STATUS_PATH: VULNERABLE_INSTANCE_PATH,
	}
	for path: String in expectations.keys():
		assert_true(FileAccess.file_exists(path), "状态数据生产脚本必须存在：%s" % path)
		assert_true(
			FileAccess.file_exists(expectations[path]),
			"对应的 GDScript 生产实例必须存在：%s" % expectations[path]
		)
		var text: String = FileAccess.get_file_as_string(path)
		assert_true(text.contains(base_extends), "状态数据必须继承 GDScript 基类：%s" % path)
		assert_true(
			text.contains("func CreateInstance("),
			"状态数据必须实现 CreateInstance：%s" % path
		)
		assert_true(
			text.contains(expectations[path]),
			"状态数据必须声明指向 GDScript 生产实例的脚本路径：%s" % path
		)

	var guard_data: Resource = load(ATTRIBUTE_CHANGE_GUARD_STATUS_PATH).new()
	track(guard_data)
	assert_eq(int(guard_data.get("TargetAttribute")), 0, "拦截目标属性默认值必须与旧 C# 一致。")
	assert_eq(int(guard_data.get("Direction")), 0, "拦截方向默认值必须是 Any。")
	assert_false(bool(guard_data.get("CancelChange")), "取消开关默认值必须是 false。")
	assert_eq(float(guard_data.get("DeltaMultiplier")), 1.0, "变化量倍率默认值必须与旧 C# 一致。")
	assert_false(bool(guard_data.get("EnableMinValue")), "下限开关默认值必须是 false。")
	assert_eq(float(guard_data.get("MinValue")), 0.0, "下限默认值必须与旧 C# 一致。")
	assert_false(bool(guard_data.get("EnableMaxValue")), "上限开关默认值必须是 false。")
	assert_eq(float(guard_data.get("MaxValue")), 0.0, "上限默认值必须与旧 C# 一致。")

	var cap_data: Resource = load(BOSS_DAMAGE_CAP_STATUS_PATH).new()
	track(cap_data)
	assert_eq(
		float(cap_data.get("MaxHealthDamageRatio")),
		0.1,
		"Boss 单次扣血上限比例默认值必须与旧 C# 一致。"
	)

	var flat_hit_count_data: Resource = load(HIT_COUNT_MODIFIER_STATUS_PATH).new()
	track(flat_hit_count_data)
	assert_eq(
		int(flat_hit_count_data.get("FlatHitCountBonusPerStack")),
		0,
		"段数加成默认值必须与旧 C# 一致。"
	)
	assert_eq(
		int(flat_hit_count_data.get("AttackSkillUses")),
		0,
		"段数修正的攻击技能次数默认值必须与旧 C# 一致。"
	)

	var segment_bonus_data: Resource = load(NEXT_ATTACK_DAMAGE_BONUS_STATUS_PATH).new()
	track(segment_bonus_data)
	assert_eq(
		int(segment_bonus_data.get("FlatSegmentDamageBonusPerStack")),
		0,
		"每段伤害加成默认值必须与旧 C# 一致。"
	)
	assert_eq(
		int(segment_bonus_data.get("AttackSkillUses")),
		1,
		"每段伤害修正的攻击技能次数默认值必须与旧 C# 一致。"
	)

	var vulnerable_data: Resource = load(VULNERABLE_STATUS_PATH).new()
	track(vulnerable_data)
	assert_eq(
		int(vulnerable_data.get("TargetDamageType")),
		0,
		"脆弱目标伤害类型默认值必须是 Physical。"
	)
	assert_eq(
		float(vulnerable_data.get("DamageMultiplier")),
		1.5,
		"脆弱增伤倍率默认值必须与旧 C# 一致。"
	)

	var protocol_text: String = CS_OPTIONAL.read(PROTOCOL_PATH)
	if not protocol_text.is_empty():
		assert_true(
			protocol_text.contains("public static bool ReadBool(Resource data, string field)"),
			"字段协议必须提供布尔读取，供拦截开关与上下限开关使用。"
		)

	var source := Node.new()
	var owner := Node.new()
	track(source)
	track(owner)

	# 段数修正：限次次数必须从 GDScript 数据流进 GDScript 实例。
	var hit_count_data: Resource = load(HIT_COUNT_MODIFIER_STATUS_PATH).new()
	track(hit_count_data)
	hit_count_data.set("Id", &"hit_count_probe")
	hit_count_data.set("FlatHitCountBonusPerStack", 2)
	hit_count_data.set("AttackSkillUses", 2)
	var hit_count_instance: Variant = hit_count_data.call("CreateInstance", source, owner)
	track(hit_count_instance)
	assert_true(hit_count_instance != null, "GDScript 段数修正数据必须能创建 GDScript 实例。")
	if hit_count_instance != null:
		assert_eq(
			str(hit_count_instance.get_script().resource_path),
			HIT_COUNT_MODIFIER_INSTANCE_PATH,
			"段数修正状态必须创建对应的 GDScript 实例。"
		)
		assert_eq(
			int(hit_count_instance.get("RemainingAttackSkillUses")),
			2,
			"GDScript 实例必须从 GDScript 数据读到限次的攻击技能次数。"
		)

	# 每段基础伤害修正：0 表示不限次数，必须原样传给 GDScript 实例。
	var segment_bonus_probe: Resource = load(NEXT_ATTACK_DAMAGE_BONUS_STATUS_PATH).new()
	track(segment_bonus_probe)
	segment_bonus_probe.set("Id", &"segment_bonus_probe")
	segment_bonus_probe.set("FlatSegmentDamageBonusPerStack", 10)
	segment_bonus_probe.set("AttackSkillUses", 0)
	var segment_bonus_instance: Variant = segment_bonus_probe.call(
		"CreateInstance",
		source,
		owner
	)
	track(segment_bonus_instance)
	assert_true(segment_bonus_instance != null, "GDScript 每段伤害修正数据必须能创建 GDScript 实例。")
	if segment_bonus_instance != null:
		assert_eq(
			str(segment_bonus_instance.get_script().resource_path),
			NEXT_ATTACK_DAMAGE_BONUS_INSTANCE_PATH,
			"每段伤害修正状态必须创建对应的 GDScript 实例。"
		)
		assert_eq(
			int(segment_bonus_instance.get("RemainingAttackSkillUses")),
			0,
			"不限次数时 GDScript 实例的剩余次数必须保持 0。"
		)

	# 拦截、扣血上限与脆弱：本批先锁定实例归属，行为细节由各自 Hook 的既有契约覆盖。
	var guard_probe: Resource = load(ATTRIBUTE_CHANGE_GUARD_STATUS_PATH).new()
	track(guard_probe)
	guard_probe.set("Id", &"guard_probe")
	var guard_instance: Variant = guard_probe.call("CreateInstance", source, owner)
	track(guard_instance)
	assert_true(guard_instance != null, "GDScript 属性变化拦截数据必须能创建 GDScript 实例。")
	if guard_instance != null:
		assert_eq(
			str(guard_instance.get_script().resource_path),
			ATTRIBUTE_CHANGE_GUARD_INSTANCE_PATH,
			"属性变化拦截状态必须创建对应的 GDScript 实例。"
		)

	var cap_probe: Resource = load(BOSS_DAMAGE_CAP_STATUS_PATH).new()
	track(cap_probe)
	cap_probe.set("Id", &"damage_cap_probe")
	cap_probe.set("MaxHealthDamageRatio", 0.25)
	var cap_instance: Variant = cap_probe.call("CreateInstance", source, owner)
	track(cap_instance)
	assert_true(cap_instance != null, "GDScript 扣血上限数据必须能创建 GDScript 实例。")
	if cap_instance != null:
		assert_eq(
			str(cap_instance.get_script().resource_path),
			BOSS_DAMAGE_CAP_INSTANCE_PATH,
			"扣血上限状态必须创建对应的 GDScript 实例。"
		)

	var vulnerable_probe: Resource = load(VULNERABLE_STATUS_PATH).new()
	track(vulnerable_probe)
	vulnerable_probe.set("Id", &"vulnerable_probe")
	var vulnerable_instance: Variant = vulnerable_probe.call("CreateInstance", source, owner)
	track(vulnerable_instance)
	assert_true(vulnerable_instance != null, "GDScript 脆弱数据必须能创建 GDScript 实例。")
	if vulnerable_instance != null:
		assert_eq(
			str(vulnerable_instance.get_script().resource_path),
			VULNERABLE_INSTANCE_PATH,
			"脆弱状态必须创建对应的 GDScript 实例。"
		)
