@tool
extends McpTestSuite

## 战斗技能与效果（CombatSkillData / CardEffect 家族）生产迁移契约套件。
##
## 套件锁定四件事：技能与效果资产改用 GDScript 生产实现、序列化数值未变、旧 C# 垫片与
## 跨语言协议同时保留、C# 消费方不再按旧类型声明技能与效果容器。
## 运行时的“技能真的打出伤害/真的施加状态”由运行中的游戏经 game_eval 验证。
## C# 物理退役后，依赖垫片的对照断言经 CS_OPTIONAL 自动退场（见 tests/godot/csharp_optional.gd）。
## 注意：生产脚本的等价改写必须经 script_patch 触发重载，否则编辑器内存里仍是旧脚本。

## 本批 GDScript 生产脚本路径。
const CARD_EFFECT_SCRIPT_PATH: String = "res://core/combat/effects/card_effect.gd"
const DAMAGE_EFFECT_SCRIPT_PATH: String = "res://core/combat/effects/damage_effect.gd"
const MODIFY_ATTRIBUTE_SCRIPT_PATH: String = \
	"res://core/combat/effects/modify_attribute_effect.gd"
const APPLY_SHIELD_SCRIPT_PATH: String = \
	"res://core/combat/effects/apply_shield_card_effect.gd"
const APPLY_STATUS_SCRIPT_PATH: String = \
	"res://core/combat/effects/apply_status_card_effect.gd"
const COMBAT_SKILL_SCRIPT_PATH: String = "res://core/combat/skills/combat_skill_data.gd"

## 旧 C# 兼容垫片路径。
const LEGACY_CARD_EFFECT_PATH: String = "res://core/combat/effects/CardEffect.cs"
const LEGACY_DAMAGE_EFFECT_PATH: String = "res://core/combat/effects/DamageEffect.cs"
const LEGACY_COMBAT_SKILL_PATH: String = "res://core/combat/skills/CombatSkillData.cs"

## 跨语言协议路径。
const CARD_EFFECT_PROTOCOL_PATH: String = "res://core/combat/effects/CardEffectProtocol.cs"
const COMBAT_SKILL_PROTOCOL_PATH: String = "res://core/combat/skills/CombatSkillDataProtocol.cs"

## 效果基类的 GDScript 生产脚本路径。
const CARD_EFFECT_GD: String = "res://core/combat/effects/card_effect.gd"

## 技能执行上下文族的 GDScript 生产脚本路径。
const SKILL_TARGET_GD: String = "res://core/combat/skills/skill_target.gd"
const SKILL_CONTEXT_GD: String = "res://core/combat/skills/skill_execution_context.gd"
const MODIFIER_CONTEXT_GD: String = "res://core/combat/skills/skill_execution_modifier_context.gd"
const HIT_COUNT_CONTEXT_GD: String = \
	"res://core/combat/effects/damage_effect_hit_count_context.gd"
const SEGMENT_CONTEXT_GD: String = \
	"res://core/combat/effects/damage_effect_segment_context.gd"

## 技能执行上下文族的旧 C# 垫片路径（必须继续保留）。
const SKILL_CONTEXT_CS: String = "res://core/combat/skills/SkillExecutionContext.cs"
const MODIFIER_CONTEXT_CS: String = \
	"res://core/combat/skills/SkillExecutionModifierContext.cs"

## 目标选择族的 GDScript 生产脚本路径。
const SELECTION_GD: String = "res://core/combat/effects/skill_effect_target_selection.gd"
const SCOPE_UTILITY_GD: String = \
	"res://core/combat/effects/skill_effect_target_scope_utility.gd"
const SCOPE_ENUM_GD: String = "res://core/combat/effects/skill_effect_target_scope.gd"
const HIT_MODE_ENUM_GD: String = "res://core/combat/effects/damage_hit_target_mode.gd"
const ROLE_ENUM_GD: String = "res://core/combat/skills/skill_target_role.gd"

## 技能与技能卡资产目录。
const COMBAT_SKILL_DIR: String = "res://resources/combat_skills"
const SKILL_CARD_DIR: String = "res://resources/skill_cards"

## 迁移期 C# 可选助手：C# 退役后 C# 对照断言自动退场，GDScript 侧断言照跑。
## 说明见 tests/godot/csharp_optional.gd。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## 需要保持「可被 GDScript 实例化」的跨语言 DTO 脚本（迁移期是 C# 垫片）。
const DTO_SCRIPT_PATHS: Array[String] = [
	"res://core/combat/skills/SkillTarget.cs",
	"res://core/combat/skills/SkillExecutionContext.cs",
	"res://core/combat/skills/SkillExecutionModifierContext.cs",
	"res://core/combat/effects/DamageEffectHitCountContext.cs",
	"res://core/combat/effects/DamageEffectSegmentContext.cs",
	"res://core/combat/DamagePayload.cs",
]

## 相关场景与触发式 buff 资产路径。
const BATTLE_SCENE_PATH: String = "res://scenes/battle_scenes/battle.tscn"
const MONSTER_SCENE_PATH: String = "res://scenes/monster_scenes/monster.tscn"
const TRIGGER_BUFF_PATH: String = "res://resources/buffs/draw_when_physAtk_decreased.tres"

## 迁移前技能资产数量，必须保持不变。
const COMBAT_SKILL_ASSET_COUNT: int = 69
const SKILL_CARD_ASSET_COUNT: int = 69

## 旧 C# 脚本路径，任何资产都不应再引用。
const LEGACY_SCRIPT_MARKERS: Array[String] = [
	"CardEffect.cs",
	"DamageEffect.cs",
	"CombatSkillData.cs",
	"ApplyStatusCardEffect.cs",
	"ApplyShieldCardEffect.cs",
	"ModifyAttributeEffect.cs",
]


## 返回 GodotAI 使用的稳定套件名称。
##
## @return 战斗技能契约套件名。
func suite_name() -> String:
	return "combat_skill_contract"


## 验证生产脚本存在且继承关系与迁移设计一致。
func test_production_scripts_exist_and_inherit() -> void:
	for path: String in [
		CARD_EFFECT_SCRIPT_PATH,
		DAMAGE_EFFECT_SCRIPT_PATH,
		MODIFY_ATTRIBUTE_SCRIPT_PATH,
		APPLY_SHIELD_SCRIPT_PATH,
		APPLY_STATUS_SCRIPT_PATH,
		COMBAT_SKILL_SCRIPT_PATH,
	]:
		assert_true(FileAccess.file_exists(path), "生产脚本必须存在：%s" % path)

	var card_effect: String = FileAccess.get_file_as_string(CARD_EFFECT_SCRIPT_PATH)
	assert_true(card_effect.contains("extends Resource"), "效果基类必须直接继承 Resource。")
	assert_true(card_effect.contains("func Execute("), "效果基类必须声明 Execute 协议。")
	assert_true(card_effect.contains("func _select_scope_targets("), "效果基类必须提供目标解析。")
	assert_true(card_effect.contains("func _find_status_component("), "效果基类必须提供状态组件查找。")

	for path: String in [
		DAMAGE_EFFECT_SCRIPT_PATH,
		MODIFY_ATTRIBUTE_SCRIPT_PATH,
		APPLY_SHIELD_SCRIPT_PATH,
		APPLY_STATUS_SCRIPT_PATH,
	]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_true(
			text.contains('extends "%s"' % CARD_EFFECT_SCRIPT_PATH),
			"效果脚本必须继承 GDScript 效果基类：%s" % path
		)
		assert_true(text.contains("func Execute("), "效果脚本必须实现 Execute：%s" % path)

	var skill_text: String = FileAccess.get_file_as_string(COMBAT_SKILL_SCRIPT_PATH)
	assert_true(
		skill_text.contains('extends "res://resources/item/base_card_data.gd"'),
		"战斗技能必须复用字段名一致的 GDScript BaseCardData。"
	)
	assert_true(skill_text.contains("func Execute("), "战斗技能必须实现 Execute。")
	assert_true(skill_text.contains("func RequiresTarget("), "战斗技能必须保留 RequiresTarget。")
	assert_true(
		skill_text.contains("@export var Effects: Array[Resource] = []"),
		"战斗技能的效果容器必须是通用 Resource 数组。"
	)


## 验证 GDScript 效果与技能的默认值同旧 C# 字段默认值一致。
func test_gdscript_defaults_match_legacy_fields() -> void:
	var damage: Resource = load(DAMAGE_EFFECT_SCRIPT_PATH).new()
	track(damage)
	assert_eq(int(damage.get("BaseDamage")), 10, "基础伤害默认值必须与旧 C# 一致。")
	assert_eq(int(damage.get("HitCount")), 1, "段数默认值必须与旧 C# 一致。")
	assert_eq(int(damage.get("HitTargetMode")), 0, "段目标模式默认值必须与旧 C# 一致。")
	assert_eq(int(damage.get("Type")), 0, "伤害类型默认值必须与旧 C# 一致。")
	assert_eq(int(damage.get("Element")), 0, "五行属性默认值必须与旧 C# 一致。")
	assert_eq(int(damage.get("TargetScope")), 2, "目标范围默认值必须为 PrimaryOnly。")
	assert_true(
		is_equal_approx(float(damage.get("PrimaryDamageMultiplier")), 1.0),
		"主目标倍率默认值必须与旧 C# 一致。"
	)
	assert_true(
		is_equal_approx(float(damage.get("SecondaryDamageMultiplier")), 1.0),
		"次目标倍率默认值必须与旧 C# 一致。"
	)

	var modify: Resource = load(MODIFY_ATTRIBUTE_SCRIPT_PATH).new()
	track(modify)
	assert_eq(int(modify.get("TargetAttribute")), 4, "属性目标默认值必须为 Speed（4）。")
	assert_true(is_equal_approx(float(modify.get("Amount")), 20.0), "属性加成默认值必须为 20。")
	assert_eq(int(modify.get("TargetScope")), 2, "属性效果目标范围默认值必须为 PrimaryOnly。")

	var shield: Resource = load(APPLY_SHIELD_SCRIPT_PATH).new()
	track(shield)
	assert_eq(int(shield.get("TargetScope")), 1, "护盾效果目标范围默认值必须为 AllTargets。")
	assert_eq(shield.get("ShieldStatus"), null, "护盾状态默认值必须为 null。")

	var status: Resource = load(APPLY_STATUS_SCRIPT_PATH).new()
	track(status)
	assert_eq(int(status.get("TargetScope")), 1, "状态效果目标范围默认值必须为 AllTargets。")
	assert_eq(status.get("Status"), null, "状态资源默认值必须为 null。")

	var skill: Resource = load(COMBAT_SKILL_SCRIPT_PATH).new()
	track(skill)
	assert_eq(int(skill.get("Element")), 0, "技能五行属性默认值必须为 None。")
	assert_eq(int(skill.get("TargetingType")), 1, "技能目标类型默认值必须为 SingleEnemy。")
	assert_eq(str(skill.get("CardName")), "", "技能卡名默认值必须为空字符串。")
	assert_eq(str(skill.get("CardId")), "", "技能卡标识默认值必须为空。")
	assert_true(skill.get("Effects") is Array, "技能效果容器必须是数组。")
	assert_eq((skill.get("Effects") as Array).size(), 0, "技能效果容器默认必须为空。")


## 验证技能需要显式选择目标的判定与旧 C# RequiresTarget 完全一致。
func test_requires_target_matches_legacy_rule() -> void:
	var skill: Resource = load(COMBAT_SKILL_SCRIPT_PATH).new()
	track(skill)
	# 0=Self、2=AllEnemies、4=AllUnits、5=RandomEnemy 不需要显式目标；其余需要。
	var expectations := {
		0: false, 1: true, 2: false, 3: true, 4: false, 5: false, 6: true,
	}
	for targeting_type: int in expectations.keys():
		skill.set("TargetingType", targeting_type)
		assert_eq(
			bool(skill.call("RequiresTarget")),
			bool(expectations[targeting_type]),
			"目标类型 %d 的 RequiresTarget 必须与旧 C# 一致。" % targeting_type
		)


## 验证 GDScript 效果的目标解析与伤害倍率计算与旧 C# 规则一致。
func test_damage_effect_selection_and_multipliers() -> void:
	var damage: Resource = load(DAMAGE_EFFECT_SCRIPT_PATH).new()
	track(damage)
	damage.set("BaseDamage", 10)
	damage.set("PrimaryDamageMultiplier", 2.0)
	damage.set("SecondaryDamageMultiplier", 0.5)

	var source := Node.new()
	track(source)
	var primary := Node.new()
	track(primary)
	var secondary := Node.new()
	track(secondary)

	var context := FakeContext.new()
	track(context)
	context.Source = source
	context.CandidateTargets = [primary, secondary]
	context.Targets = [
		FakeTarget.new(primary, 0),
		FakeTarget.new(secondary, 1),
	]

	var all_targets: Array = damage.call("_select_scope_targets", context, 1)
	assert_eq(all_targets.size(), 2, "AllTargets 必须命中上下文中的全部目标。")
	var primary_only: Array = damage.call("_select_scope_targets", context, 2)
	assert_eq(primary_only.size(), 1, "PrimaryOnly 只能命中主目标。")
	assert_true(primary_only[0]["Unit"] == primary, "PrimaryOnly 必须命中主目标节点。")
	var secondary_only: Array = damage.call("_select_scope_targets", context, 3)
	assert_eq(secondary_only.size(), 1, "SecondaryOnly 只能命中次目标。")
	assert_true(secondary_only[0]["Unit"] == secondary, "SecondaryOnly 必须命中次目标节点。")
	var self_only: Array = damage.call("_select_scope_targets", context, 0)
	assert_eq(self_only.size(), 1, "Source 范围只能命中施放者自身。")
	assert_true(self_only[0]["IsSource"], "Source 范围必须标记 IsSource。")

	assert_eq(int(damage.call("_calculate_damage_for_target", primary_only[0])), 20,
		"主目标伤害必须按主目标倍率取整。")
	assert_eq(int(damage.call("_calculate_damage_for_target", secondary_only[0])), 5,
		"次目标伤害必须按次目标倍率取整。")
	assert_eq(int(damage.call("_calculate_damage_for_target", self_only[0])), 20,
		"施放者自身伤害必须按主目标倍率计算。")

	var valid: Array = damage.call("_select_valid_candidates", context.CandidateTargets)
	assert_eq(valid.size(), 0, "缺少生命组件的候选目标必须被过滤。")


## 验证战斗技能的伤害效果识别同时覆盖 C# 垫片与 GDScript 实现。
func test_combat_skill_detects_damage_effect() -> void:
	var skill: Resource = load(COMBAT_SKILL_SCRIPT_PATH).new()
	track(skill)
	var damage: Resource = load(DAMAGE_EFFECT_SCRIPT_PATH).new()
	track(damage)
	var plain := PlainEffect.new()
	track(plain)

	assert_eq(
		str(damage.get_script().resource_path),
		DAMAGE_EFFECT_SCRIPT_PATH,
		"伤害效果实例必须由 GDScript 伤害效果脚本创建。"
	)
	# 直接向导出的 Array[Resource] 追加条目，避免测试替身构造成未类型化数组后丢元素。
	var effects: Array = skill.get("Effects")
	effects.append(plain)
	assert_false(bool(skill.call("_has_damage_effect")), "只有普通效果时不得判定为伤害技能。")
	effects.append(damage)
	assert_eq(effects.size(), 2, "效果容器必须保留两个条目。")
	assert_true(bool(skill.call("_has_damage_effect")), "包含 GDScript 伤害效果时必须判定为伤害技能。")
	effects.clear()
	effects.append(null)
	assert_false(bool(skill.call("_has_damage_effect")), "空效果不得被判定为伤害效果。")


## 去掉整行注释，仅保留可执行代码行（用于「不得再出现某写法」的断言）。
##
## @param source GDScript 源码。
## @return 去掉注释行后的源码。
func _code_only(source: String) -> String:
	var out: String = ""
	for line: String in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out += line + "\n"
	return out


## 伤害效果识别必须只按导出字段协议，不得再引用 C# 类型名或脚本路径。
##
## 旧实现用 `effect is DamageEffect`（语言身份判定）：C# 垫片退役后该标识符无法解析，
## 脚本会直接加载失败；字段协议让两种语言的实现共用同一判据。
func test_damage_effect_detection_is_field_based() -> void:
	var source: String = FileAccess.get_file_as_string(COMBAT_SKILL_SCRIPT_PATH)
	var code_only: String = _code_only(source)
	assert_true(
		source.contains("const DAMAGE_EFFECT_REQUIRED_FIELDS: Array[StringName] = ["),
		"技能脚本必须声明伤害效果字段协议。"
	)
	for field: String in ["&\"BaseDamage\"", "&\"HitCount\"", "&\"PrimaryDamageMultiplier\""]:
		assert_true(source.contains(field), "伤害效果协议必须包含字段：%s" % field)
	assert_true(source.contains("func _is_damage_effect("), "技能脚本必须提供伤害效果字段判定。")
	# 只看代码行：说明性注释里仍会提到旧写法，属于文档而非依赖。
	assert_true(not code_only.contains("is DamageEffect"), "不得再按旧 C# 类型名判定伤害效果。")
	assert_true(not code_only.contains("DAMAGE_EFFECT_SCRIPT_PATH"), "不得再按脚本路径判定伤害效果。")

	var skill: Resource = load(COMBAT_SKILL_SCRIPT_PATH).new()
	track(skill)
	var damage: Resource = load(DAMAGE_EFFECT_SCRIPT_PATH).new()
	track(damage)
	var plain := PlainEffect.new()
	track(plain)
	assert_true(bool(skill.call("_is_damage_effect", damage)), "字段协议必须接受 GDScript 伤害效果。")
	assert_false(bool(skill.call("_is_damage_effect", plain)), "字段协议不得把普通效果判成伤害效果。")
	assert_false(bool(skill.call("_is_damage_effect", null)), "字段协议不得把空值判成伤害效果。")

	# 旧 C# 垫片仍应被同一字段协议接受；C# 退役后该分支自动跳过。
	var legacy_script: Script = CS_OPTIONAL.script(LEGACY_DAMAGE_EFFECT_PATH)
	if legacy_script != null:
		var legacy_damage: Resource = legacy_script.new()
		track(legacy_damage)
		assert_true(bool(skill.call("_is_damage_effect", legacy_damage)), "字段协议必须接受旧 C# DamageEffect。")


## 验证全部技能与技能卡资产改用 GDScript 生产脚本。
func test_all_combat_assets_switched_to_gdscript() -> void:
	_assert_directory_switched(COMBAT_SKILL_DIR, COMBAT_SKILL_ASSET_COUNT, true)
	_assert_directory_switched(SKILL_CARD_DIR, SKILL_CARD_ASSET_COUNT, false)


## 验证场景与触发式 buff 资产不再引用旧 C# 效果/技能脚本。
func test_scenes_and_trigger_assets_switched() -> void:
	for path: String in [BATTLE_SCENE_PATH, MONSTER_SCENE_PATH, TRIGGER_BUFF_PATH]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_true(text.length() > 0, "必须能读取资产：%s" % path)
		for marker: String in LEGACY_SCRIPT_MARKERS:
			assert_false(
				text.contains(marker),
				"%s 不得再引用旧 C# 脚本 %s。" % [path, marker]
			)
		if path != TRIGGER_BUFF_PATH:
			assert_true(
				text.contains(COMBAT_SKILL_SCRIPT_PATH),
				"%s 必须引用 GDScript 战斗技能脚本。" % path
			)


## 验证旧 C# 垫片与跨语言协议同时保留。
func test_legacy_shims_and_protocols_kept() -> void:
	if not CS_OPTIONAL.present_all(
		[LEGACY_CARD_EFFECT_PATH, LEGACY_DAMAGE_EFFECT_PATH, LEGACY_COMBAT_SKILL_PATH, CARD_EFFECT_PROTOCOL_PATH, COMBAT_SKILL_PROTOCOL_PATH]
	):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	for path: String in [
		LEGACY_CARD_EFFECT_PATH,
		LEGACY_DAMAGE_EFFECT_PATH,
		LEGACY_COMBAT_SKILL_PATH,
	]:
		assert_true(FileAccess.file_exists(path), "旧 C# 垫片必须保留：%s" % path)

	var damage_shim: String = FileAccess.get_file_as_string(LEGACY_DAMAGE_EFFECT_PATH)
	for field: String in [
		"BaseDamage", "HitCount", "HitTargetMode", "Type", "Element", "TargetScope",
		"PrimaryDamageMultiplier", "SecondaryDamageMultiplier",
	]:
		assert_true(damage_shim.contains(field), "伤害效果垫片必须保留字段 %s。" % field)

	var effect_protocol: String = FileAccess.get_file_as_string(CARD_EFFECT_PROTOCOL_PATH)
	assert_true(
		effect_protocol.contains('CardEffectScriptPath = "%s"' % CARD_EFFECT_SCRIPT_PATH),
		"效果协议必须声明生产基类脚本路径。"
	)
	assert_true(
		effect_protocol.contains('DamageEffectScriptPath = "%s"' % DAMAGE_EFFECT_SCRIPT_PATH),
		"效果协议必须声明伤害效果脚本路径。"
	)
	assert_true(effect_protocol.contains("IsDamageEffect"), "效果协议必须提供伤害效果识别。")
	assert_true(effect_protocol.contains("public static bool Execute("), "效果协议必须提供执行入口。")

	var skill_protocol: String = FileAccess.get_file_as_string(COMBAT_SKILL_PROTOCOL_PATH)
	assert_true(
		skill_protocol.contains('ScriptPath = "%s"' % COMBAT_SKILL_SCRIPT_PATH),
		"技能协议必须声明生产脚本路径。"
	)
	assert_true(skill_protocol.contains("FilterSkills"), "技能协议必须提供技能数组过滤。")
	assert_true(skill_protocol.contains("RequiresTarget"), "技能协议必须提供目标需求判定。")
	assert_true(skill_protocol.contains("ReadDisplayName"), "技能协议必须提供显示名读取。")


## 验证 C# 消费方改用通用 Resource 与协议，不再按旧类型声明容器。
func test_csharp_consumers_use_resource_and_protocol() -> void:
	var expectations := {
		"res://entities/Monster.cs": ["Array<Resource>", "CombatSkillDataProtocol"],
		"res://entities/components/MonsterSkillComponent.cs": [
			"Array<Resource>", "CombatSkillDataProtocol",
		],
		"res://resources/item/card/SkillCardData.cs": [
			"public Resource Skill", "CombatSkillDataProtocol",
		],
		"res://core/combat/skills/CombatSkillData.cs": [
			"CardEffectProtocol", "public Array Effects",
		],
		"res://core/combat/status/AttributeChangeTriggerStatusInstance.cs": [
			"CardEffectProtocol",
		],
		"res://core/combat/skills/SkillExecutionModifierContext.cs": ["Resource skill"],
		"res://core/combat/effects/DamageEffectSegmentContext.cs": ["Variant target"],
	}
	# C# 消费方对照：任一垫片退役即整例退场，避免留下半套断言的假阳性。
	var consumer_paths: Array = expectations.keys()
	consumer_paths.append("res://entities/components/StatusComponent.cs")
	if not CS_OPTIONAL.present_all(consumer_paths):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	for path: String in expectations.keys():
		var text: String = FileAccess.get_file_as_string(path)
		assert_true(text.length() > 0, "必须能读取消费者源码：%s" % path)
		for marker: String in expectations[path]:
			assert_true(text.contains(marker), "%s 必须包含 %s。" % [path, marker])
		assert_false(
			text.contains("Array<CombatSkillData>"),
			"%s 不得再声明强类型 Array<CombatSkillData>。" % path
		)
		assert_false(
			text.contains("Array<CardEffect>"),
			"%s 不得再声明强类型 Array<CardEffect>。" % path
		)

	var status_component: String = FileAccess.get_file_as_string(
		"res://entities/components/StatusComponent.cs"
	)
	assert_true(
		status_component.contains("ApplyDamageHitCountModifiers"),
		"状态组件必须提供段数修正的非 ref 包装。"
	)
	assert_true(
		status_component.contains("ApplyDamageEffectSegmentDamageModifiers"),
		"状态组件必须提供单段伤害修正的非 ref 包装。"
	)


## 验证代表性技能资产的序列化数值未变。
func test_serialized_skill_values_preserved() -> void:
	var skill: Resource = load("res://resources/combat_skills/fire_phys_huoji.tres")
	assert_true(skill != null, "必须能加载火击技能资产。")
	if skill == null:
		return
	assert_eq(
		str(skill.get_script().resource_path),
		COMBAT_SKILL_SCRIPT_PATH,
		"技能资产必须使用 GDScript 战斗技能脚本。"
	)
	assert_eq(str(skill.get("CardName")), "火击", "技能名称必须保持不变。")
	assert_eq(int(skill.get("Element")), 5, "技能五行属性必须保持不变。")
	assert_eq(int(skill.get("TargetingType")), 1, "技能目标类型必须保持不变。")
	var effects: Array = skill.get("Effects")
	assert_eq(effects.size(), 1, "技能必须保留一个伤害效果。")
	var effect: Resource = effects[0]
	assert_eq(
		str(effect.get_script().resource_path),
		DAMAGE_EFFECT_SCRIPT_PATH,
		"效果子资源必须使用 GDScript 伤害效果脚本。"
	)
	assert_eq(int(effect.get("BaseDamage")), 5, "效果基础伤害必须保持不变。")
	assert_eq(int(effect.get("Type")), 0, "效果伤害类型必须保持不变。")
	assert_eq(int(effect.get("Element")), 5, "效果五行属性必须保持不变。")

	var card: Resource = load("res://resources/skill_cards/fire_phys_huoji.tres")
	assert_true(card != null, "必须能加载火击技能卡资产。")
	if card == null:
		return
	assert_eq(str(card.get("CardName")), "火击", "技能卡名称必须保持不变。")
	assert_eq(int(card.get("cost")), 10, "技能卡费用必须保持不变。")
	assert_true(card.get("Skill") != null, "技能卡必须保留战斗技能引用。")


## 验证跨语言 DTO 已经是可以被 GDScript 实例化的 Godot 对象。
##
## 旧 C# 的这几个上下文/载荷原本是纯 C# 类：GDScript 既无法用 load().new() 构造，
## 也无法把它们作为 Variant 交给 C# Hook。本批把它们降级为 RefCounted 以形成显式
## 兼容边界，本测试锁定该边界不会被无意改回纯 C# 类。
## 注意：Godot 对没有默认构造函数的 C# 脚本会返回 can_instantiate()=false，因此这里
## 只断言基类；"真的能从 GDScript 构造出来"由运行中的游戏经 game_eval 验证。
func test_cross_language_dto_scripts_are_godot_objects() -> void:
	if not CS_OPTIONAL.any_present(DTO_SCRIPT_PATHS):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	for path: String in DTO_SCRIPT_PATHS:
		if not CS_OPTIONAL.present(path):
			continue
		var dto_script: Variant = load(path)
		assert_true(dto_script != null, "跨语言 DTO 脚本必须存在：%s" % path)
		if dto_script == null:
			continue
		assert_eq(
			str(dto_script.get_instance_base_type()),
			"RefCounted",
			"跨语言 DTO 必须继承 RefCounted 才能被 GDScript 构造：%s" % path
		)


## 验证技能执行上下文族已迁移到 GDScript，且静态工厂能被 GDScript 直接调用。
##
## 旧 C# 版本的关键缺陷是静态工厂无法从 GDScript 调用
## （`load("...SkillExecutionContext.cs").FromSingleTarget(...)` 运行时报 Nonexistent function），
## 而 `battle_manager.gd` / `skill_card.gd` / `attribute_change_trigger_status_instance.gd`
## 都依赖这些工厂；本用例同时锁定脚本形状、消费方路径切换与真实的工厂调用结果。
##
## @return 无返回值。
func test_skill_context_family_migrated_to_gdscript() -> void:
	for path: String in [
		SKILL_TARGET_GD,
		SKILL_CONTEXT_GD,
		MODIFIER_CONTEXT_GD,
		HIT_COUNT_CONTEXT_GD,
		SEGMENT_CONTEXT_GD,
	]:
		assert_true(FileAccess.file_exists(path), "技能上下文生产脚本必须存在：%s" % path)
		var script_text: String = FileAccess.get_file_as_string(path)
		assert_true(script_text.begins_with("extends RefCounted"), "技能上下文必须继承 RefCounted：%s" % path)
		# 只检查声明行，避免注释里提到 class_name 造成假失败。
		for raw_line: String in script_text.split("\n"):
			assert_false(
				raw_line.begins_with("class_name"),
				"技能上下文不得声明 class_name：%s" % path
			)

	var context_text: String = FileAccess.get_file_as_string(SKILL_CONTEXT_GD)
	for marker: String in [
		"var Source: Node",
		"var Targets: Array",
		"var CandidateTargets: Array[Node]",
		"var PrimaryTarget: Node",
		"static func Self(",
		"static func FromSingleTarget(",
		"static func FromPrimaryTargets(",
		"static func FromSpread(",
		"static func TargetsToNodes(",
	]:
		assert_true(context_text.contains(marker), "技能执行上下文必须保留：%s" % marker)

	var target_text: String = FileAccess.get_file_as_string(SKILL_TARGET_GD)
	for marker: String in [
		"var Unit: Node",
		"var Role: int",
		"var RoleId: int",
		"var IsPrimary: bool",
		"var IsSecondary: bool",
	]:
		assert_true(target_text.contains(marker), "技能目标必须保留：%s" % marker)

	var modifier_text: String = FileAccess.get_file_as_string(MODIFIER_CONTEXT_GD)
	for marker: String in [
		"var Source: Node",
		"var Skill: Resource",
		"var SkillContext: Variant",
		"var HasDamageEffect: bool",
		"var IsAttackSkill: bool",
		"func MarkStatusForConsumption(status_id: StringName) -> void",
		"func GetStatusIdsMarkedForConsumptionSnapshot() -> Array[StringName]",
	]:
		assert_true(modifier_text.contains(marker), "修正上下文必须保留：%s" % marker)

	assert_true(
		FileAccess.get_file_as_string(HIT_COUNT_CONTEXT_GD).contains("var BaseHitCount: int"),
		"段数上下文必须保留 BaseHitCount。"
	)
	var segment_text: String = FileAccess.get_file_as_string(SEGMENT_CONTEXT_GD)
	for marker: String in ["var Target: Variant", "var HitIndex: int", "var EffectiveHitCount: int"]:
		assert_true(segment_text.contains(marker), "单段上下文必须保留：%s" % marker)

	# 消费方路径切换：生产 GDScript 不得再按旧 C# 路径加载这些上下文。
	var expectations := {
		"res://scripts/battle_scripts/battle_manager.gd": SKILL_CONTEXT_GD,
		"res://scripts/card_scripts/skill_card.gd": SKILL_CONTEXT_GD,
		"res://core/combat/status/attribute_change_trigger_status_instance.gd": SKILL_CONTEXT_GD,
		"res://core/combat/skills/combat_skill_data.gd": MODIFIER_CONTEXT_GD,
	}
	for path: String in expectations.keys():
		assert_true(
			FileAccess.get_file_as_string(path).contains(str(expectations[path])),
			"%s 必须引用 GDScript 上下文：%s" % [path, expectations[path]]
		)
	var damage_effect_text: String = FileAccess.get_file_as_string(DAMAGE_EFFECT_SCRIPT_PATH)
	assert_true(damage_effect_text.contains(HIT_COUNT_CONTEXT_GD), "伤害效果必须引用 GDScript 段数上下文。")
	assert_true(damage_effect_text.contains(SEGMENT_CONTEXT_GD), "伤害效果必须引用 GDScript 单段上下文。")
	## C# 物理退役后这两个垫片已删除；只有垫片仍在时才要求「必须保留」。
	if CS_OPTIONAL.present_all([SKILL_CONTEXT_CS, MODIFIER_CONTEXT_CS]):
		assert_true(FileAccess.file_exists(SKILL_CONTEXT_CS), "旧 C# 技能上下文垫片必须保留。")
		assert_true(FileAccess.file_exists(MODIFIER_CONTEXT_CS), "旧 C# 修正上下文垫片必须保留。")

	# 真实调用：这两个静态工厂过去在 GDScript 里直接报 Nonexistent function。
	var context_script: GDScript = load(SKILL_CONTEXT_GD)
	var source_node := Node.new()
	var primary_node := Node.new()
	var secondary_node := Node.new()

	var single: RefCounted = context_script.FromSingleTarget(source_node, primary_node)
	assert_true(single != null, "FromSingleTarget 必须能返回上下文。")
	assert_true(single.get("Source") == source_node, "FromSingleTarget 必须保留施放者。")
	assert_eq((single.get("Targets") as Array).size(), 1, "单目标上下文必须只有一个目标。")
	assert_true(single.get("PrimaryTarget") == primary_node, "单目标上下文的主目标必须是传入目标。")
	assert_eq((single.get("CandidateTargets") as Array).size(), 1, "候选池必须回退为主目标。")
	var single_target: Variant = (single.get("Targets") as Array)[0]
	assert_true(single_target.get("Unit") == primary_node, "目标条目必须携带节点。")
	assert_true(bool(single_target.get("IsPrimary")), "目标条目必须标记为主目标。")
	assert_eq(int(single_target.get("Role")), int(single_target.get("RoleId")), "Role 与 RoleId 必须一致。")

	var self_context: RefCounted = context_script.Self(source_node)
	assert_true(self_context.get("PrimaryTarget") == source_node, "Self 必须以施放者为主目标。")

	var multi: RefCounted = context_script.FromPrimaryTargets(
		source_node, [primary_node, null, secondary_node]
	)
	assert_eq((multi.get("Targets") as Array).size(), 2, "多目标上下文必须跳过空目标。")
	assert_true(multi.get("PrimaryTarget") == primary_node, "多目标上下文的主目标必须是第一个目标。")

	var spread: RefCounted = context_script.FromSpread(
		source_node, primary_node, [secondary_node, primary_node, null]
	)
	var spread_targets: Array = spread.get("Targets")
	assert_eq(spread_targets.size(), 2, "扩散上下文必须去重主目标与空目标。")
	assert_true(bool(spread_targets[1].get("IsSecondary")), "扩散上下文的第二个目标必须是次目标。")
	assert_eq((spread.get("CandidateTargets") as Array).size(), 2, "候选池必须回退为主次目标。")

	# 修正上下文的去重与快照语义必须与旧 C# HashSet 一致。
	var skill_resource: Resource = load(COMBAT_SKILL_SCRIPT_PATH).new()
	var modifier: RefCounted = load(MODIFIER_CONTEXT_GD).new(source_node, skill_resource, single, true)
	assert_true(bool(modifier.get("IsAttackSkill")), "含伤害效果的技能必须视为攻击技能。")
	modifier.call("MarkStatusForConsumption", &"probe_status")
	modifier.call("MarkStatusForConsumption", &"probe_status")
	modifier.call("MarkStatusForConsumption", &"")
	var snapshot: Array = modifier.call("GetStatusIdsMarkedForConsumptionSnapshot")
	assert_eq(snapshot.size(), 1, "重复标记与空 Id 都不得重复计入待消费集合。")
	assert_eq(str(snapshot[0]), "probe_status", "待消费集合必须保留被标记的状态 Id。")

	# 段数与单段上下文的字段必须与旧 C# 逐字一致。
	var hit_count: RefCounted = load(HIT_COUNT_CONTEXT_GD).new(source_node, single, skill_resource, 3)
	assert_eq(int(hit_count.get("BaseHitCount")), 3, "段数上下文必须保留原始段数。")
	assert_true(hit_count.get("SkillContext") == single, "段数上下文必须保留技能上下文。")
	var segment: RefCounted = load(SEGMENT_CONTEXT_GD).new(
		source_node, single, skill_resource, {"Unit": primary_node}, 1, 4
	)
	assert_eq(int(segment.get("HitIndex")), 1, "单段上下文必须保留段号。")
	assert_eq(int(segment.get("EffectiveHitCount")), 4, "单段上下文必须保留总段数。")
	assert_true(
		(segment.get("Target") as Dictionary)["Unit"] == primary_node,
		"单段上下文必须保留选中目标。"
	)

	source_node.free()
	primary_node.free()
	secondary_node.free()


## 校验一个资产目录是否全部切换到 GDScript，并返回统计结果。
##
## @param directory_path 资产目录的 res:// 路径。
## @param expected_count 迁移前的资产数量。
## @param require_combat_script 是否要求每个资产都引用 GDScript 战斗技能脚本。
## @return 无；断言失败时记录具体文件名。
func _assert_directory_switched(
	directory_path: String,
	expected_count: int,
	require_combat_script: bool
) -> void:
	var directory: DirAccess = DirAccess.open(directory_path)
	assert_true(directory != null, "必须能打开资产目录：%s" % directory_path)
	if directory == null:
		return

	var asset_count: int = 0
	var legacy_hits: Array[String] = []
	var script_class_hits: Array[String] = []
	var missing_skill_script: Array[String] = []
	var typed_effect_arrays: Array[String] = []
	directory.list_dir_begin()
	var file_name: String = directory.get_next()
	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".tres"):
			asset_count += 1
			var text: String = FileAccess.get_file_as_string(directory_path + "/" + file_name)
			for marker: String in LEGACY_SCRIPT_MARKERS:
				if text.contains(marker):
					legacy_hits.append("%s:%s" % [file_name, marker])
			if text.contains('script_class="CombatSkillData"'):
				script_class_hits.append(file_name)
			if require_combat_script and not text.contains(COMBAT_SKILL_SCRIPT_PATH):
				missing_skill_script.append(file_name)
			if text.contains("Effects = Array[ExtResource("):
				typed_effect_arrays.append(file_name)
		file_name = directory.get_next()
	directory.list_dir_end()

	assert_eq(asset_count, expected_count, "%s 的资产数量必须保持不变。" % directory_path)
	assert_true(legacy_hits.is_empty(), "%s 仍引用旧 C# 脚本：%s" % [directory_path, str(legacy_hits)])
	assert_true(
		script_class_hits.is_empty(),
		"%s 仍声明旧 C# script_class：%s" % [directory_path, str(script_class_hits)]
	)
	assert_true(
		missing_skill_script.is_empty(),
		"%s 仍有资产未引用 GDScript 战斗技能：%s" % [directory_path, str(missing_skill_script)]
	)
	assert_true(
		typed_effect_arrays.is_empty(),
		"%s 仍有资产把效果数组声明为旧脚本类型：%s" % [directory_path, str(typed_effect_arrays)]
	)


## 验证目标选择族已迁移到 GDScript，且效果脚本收敛到同一份范围判定规则。
##
## 旧 C# 的 SkillEffectTargetScopeUtility / SkillEffectTargetSelection 是 C#-only（GDScript
## 效果脚本此前各自复制了一份判定），本用例同时锁定脚本形状、枚举取值，以及
## 「GDScript 工具类结果」与「效果脚本字典结果」在四种范围下逐项一致。
func test_target_selection_family_migrated_to_gdscript() -> void:
	for path: String in [
		SELECTION_GD,
		SCOPE_UTILITY_GD,
		SCOPE_ENUM_GD,
		HIT_MODE_ENUM_GD,
		ROLE_ENUM_GD,
	]:
		assert_true(FileAccess.file_exists(path), "目标选择族生产脚本必须存在：%s" % path)
		var text: String = FileAccess.get_file_as_string(path)
		assert_true(text.begins_with("extends RefCounted"), "目标选择族必须继承 RefCounted：%s" % path)
		for raw_line: String in text.split("\n"):
			assert_false(raw_line.begins_with("class_name"), "目标选择族不得声明 class_name：%s" % path)
		assert_false(text.contains("TODO"), "目标选择族不得保留 TODO 占位：%s" % path)

	# 枚举成员必须与旧 C# 同名同值（顺序即序列化契约）。
	var scope_text: String = FileAccess.get_file_as_string(SCOPE_ENUM_GD)
	for marker: String in [
		"enum SkillEffectTargetScope {",
		"Source = 0,",
		"AllTargets = 1,",
		"PrimaryOnly = 2,",
		"SecondaryOnly = 3,",
	]:
		assert_true(scope_text.contains(marker), "目标范围枚举必须保留：%s" % marker)

	var hit_mode_text: String = FileAccess.get_file_as_string(HIT_MODE_ENUM_GD)
	for marker: String in [
		"enum DamageHitTargetMode {",
		"ContextTargets = 0,",
		"RandomCandidatePerHit = 1,",
	]:
		assert_true(hit_mode_text.contains(marker), "段目标模式枚举必须保留：%s" % marker)

	var role_text: String = FileAccess.get_file_as_string(ROLE_ENUM_GD)
	for marker: String in ["enum SkillTargetRole {", "Primary = 0,", "Secondary = 1,"]:
		assert_true(role_text.contains(marker), "目标角色枚举必须保留：%s" % marker)

	# 工具类与效果脚本必须共用同一份判定规则（效果脚本不得再自带 _scope_matches）。
	var card_effect_text: String = FileAccess.get_file_as_string(CARD_EFFECT_GD)
	assert_true(
		card_effect_text.contains("skill_effect_target_scope_utility.gd"),
		"效果基类必须引用 GDScript 目标范围工具类。"
	)
	assert_false(
		card_effect_text.contains("func _scope_matches("),
		"效果基类不得再保留重复的范围判定实现。"
	)

	# 真实行为：合成上下文上的四种范围解析必须与效果脚本的字典结果逐项一致。
	var utility_script: GDScript = load(SCOPE_UTILITY_GD)
	var selection_script: GDScript = load(SELECTION_GD)
	var context_script: GDScript = load(SKILL_CONTEXT_GD)
	var target_script: GDScript = load(SKILL_TARGET_GD)
	assert_true(utility_script != null and selection_script != null, "目标选择族脚本必须可加载。")

	var source_node := Node.new()
	var primary_node := Node.new()
	var secondary_node := Node.new()
	var extra_node := Node.new()
	var targets: Array = [
		target_script.new(primary_node, 0),
		target_script.new(secondary_node, 1),
	]
	var context: RefCounted = context_script.new(
		source_node,
		targets,
		[primary_node, secondary_node, extra_node]
	)

	var all_nodes: Array[Node] = utility_script.SelectNodes(context, utility_script.SCOPE_ALL_TARGETS)
	assert_eq(all_nodes.size(), 2, "AllTargets 必须命中全部非空目标。")
	assert_true(all_nodes[0] == primary_node, "AllTargets 必须保持上下文顺序。")
	var primary_nodes: Array[Node] = utility_script.SelectNodes(
		context,
		utility_script.SCOPE_PRIMARY_ONLY
	)
	assert_eq(primary_nodes.size(), 1, "PrimaryOnly 必须只命中主目标。")
	assert_true(primary_nodes[0] == primary_node, "PrimaryOnly 必须命中主目标节点。")
	var secondary_nodes: Array[Node] = utility_script.SelectNodes(
		context,
		utility_script.SCOPE_SECONDARY_ONLY
	)
	assert_eq(secondary_nodes.size(), 1, "SecondaryOnly 必须只命中次目标。")
	assert_true(secondary_nodes[0] == secondary_node, "SecondaryOnly 必须命中次目标节点。")
	var source_nodes: Array[Node] = utility_script.SelectNodes(context, utility_script.SCOPE_SOURCE)
	assert_eq(source_nodes.size(), 1, "Source 必须只返回施放者自身。")
	assert_true(source_nodes[0] == source_node, "Source 必须返回施放者节点。")
	var unknown_nodes: Array[Node] = utility_script.SelectNodes(context, 99)
	assert_eq(unknown_nodes.size(), 0, "未知范围必须返回空结果。")
	var null_nodes: Array[Node] = utility_script.SelectNodes(null, utility_script.SCOPE_ALL_TARGETS)
	assert_eq(null_nodes.size(), 0, "空上下文必须返回空结果。")

	var source_selection: Variant = selection_script.FromSource(source_node)
	assert_true(bool(source_selection.IsSource), "FromSource 必须标记 IsSource。")
	assert_false(bool(source_selection.IsPrimary), "自身条目不得算作主目标。")
	assert_false(bool(source_selection.IsSecondary), "自身条目不得算作次目标。")
	var target_selection: Variant = selection_script.FromTarget(targets[1])
	assert_true(bool(target_selection.IsSecondary), "FromTarget 必须按条目角色派生次目标标记。")
	assert_true(target_selection.Unit == secondary_node, "FromTarget 必须保留目标节点。")
	assert_true(selection_script.FromTarget(null) == null, "空目标必须返回 null。")

	# 效果脚本（字典形态）与工具类（条目形态）必须给出同样的目标序列。
	var card_effect_script: GDScript = load(CARD_EFFECT_GD)
	var effect: Resource = card_effect_script.new()
	for scope: int in [
		utility_script.SCOPE_SOURCE,
		utility_script.SCOPE_ALL_TARGETS,
		utility_script.SCOPE_PRIMARY_ONLY,
		utility_script.SCOPE_SECONDARY_ONLY,
		99,
	]:
		var from_utility: Array[Node] = utility_script.SelectNodes(context, scope)
		var from_effect: Array[Node] = effect.call("_select_scope_nodes", context, scope)
		assert_eq(
			from_effect.size(),
			from_utility.size(),
			"效果脚本与工具类的目标数量必须一致（scope=%d）" % scope
		)
		if from_effect.size() == from_utility.size():
			for index: int in range(from_utility.size()):
				assert_true(
					from_effect[index] == from_utility[index],
					"效果脚本与工具类的目标顺序必须一致（scope=%d, index=%d）" % [scope, index]
				)

	# 未纳入任何范围判定的替身节点不得被误命中。
	assert_false(all_nodes.has(extra_node), "候选池中的自由节点不得被当作技能目标。")

	source_node.free()
	primary_node.free()
	secondary_node.free()
	extra_node.free()


## 模拟技能执行上下文的测试替身，字段名与旧 C# SkillExecutionContext 一致。
class FakeContext extends RefCounted:
	## 施放者节点。
	var Source: Node
	## 目标集合。
	var Targets: Array = []
	## 随机候选目标集合。
	var CandidateTargets: Array = []


## 模拟技能目标的测试替身，字段名与旧 C# SkillTarget 一致。
class FakeTarget extends RefCounted:
	## 目标节点。
	var Unit: Node
	## 目标角色枚举整数。
	var Role: int
	## 是否主目标。
	var IsPrimary: bool
	## 是否次目标。
	var IsSecondary: bool

	## 构造目标替身。
	##
	## @param unit 目标节点。
	## @param role 目标角色枚举整数。
	## @return 无。
	func _init(unit: Node, role: int) -> void:
		Unit = unit
		Role = role
		IsPrimary = role == 0
		IsSecondary = role == 1


## 不含伤害语义的普通效果替身，用于验证伤害效果识别不会误判。
class PlainEffect extends Resource:
	## 占位效果协议，保持与效果家族一致的调用名。
	##
	## @param _context 技能执行上下文。
	## @return 无。
	func Execute(_context: RefCounted) -> void:
		pass
