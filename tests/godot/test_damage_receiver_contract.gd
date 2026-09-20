@tool
extends McpTestSuite

## 伤害接收组件（DamageReceiverComponent）生产迁移契约套件。
##
## 套件锁定四件事：结算链改用 GDScript 生产实现、伤害公式与五行矩阵逐项等价旧 C#、
## 两个实体场景完成脚本切换、C# 消费者与兼容垫片保留同样的方法协议边界。
## 运行时“真的能扣血、能发出 DamageResolved、能经状态组件修正”由运行中的游戏经
## game_eval 验证，编辑器侧只锁定形状、公式与枚举同步，避免依赖非 @tool 脚本的编辑器实例化。
## C# 物理退役后，依赖垫片的对照断言经 CS_OPTIONAL 自动退场（见 tests/godot/csharp_optional.gd）。

## 本批 GDScript 生产脚本与其 uid 旁车。
const DAMAGE_RECEIVER_GD: String = "res://entities/components/damage_receiver_component.gd"
const DAMAGE_RECEIVER_UID_PATH: String = "res://entities/components/damage_receiver_component.gd.uid"
const DAMAGE_FORMULA_GD: String = "res://core/combat/damage_formula.gd"
const ELEMENTAL_SYSTEM_GD: String = "res://core/combat/elemental_system.gd"

## 旧 C# 实现与消费方。
const DAMAGE_RECEIVER_CS: String = "res://entities/components/DamageReceiverComponent.cs"
const DAMAGE_FORMULA_CS: String = "res://core/combat/DamageFormula.cs"
const ELEMENTAL_SYSTEM_CS: String = "res://core/combat/ElementalSystem.cs"
const COMBAT_CONSTANTS_CS: String = "res://core/constants/CombatConstants.cs"
const ELEMENT_TYPE_CS: String = "res://core/constants/ElementType.cs"
const DAMAGE_PAYLOAD_CS: String = "res://core/combat/DamagePayload.cs"
## 伤害载荷的生产脚本（本批迁移目标）。
const DAMAGE_PAYLOAD_GD: String = "res://core/combat/damage_payload.gd"
const DAMAGE_EFFECT_CS: String = "res://core/combat/effects/DamageEffect.cs"
const BURN_STATUS_INSTANCE_CS: String = "res://core/combat/buffs/BurnStatusInstance.cs"
## 结算结果的生产脚本与旧 C# 垫片。
const DAMAGE_RESULT_GD: String = "res://core/combat/damage_resolution_result.gd"
const DAMAGE_RESULT_CS: String = "res://core/combat/DamageResolutionResult.cs"

## 迁移期 C# 可选助手：C# 退役后 C# 对照断言自动退场，GDScript 侧断言照跑。
## 说明见 tests/godot/csharp_optional.gd。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## 本批切换脚本引用的实体场景。
const PLAYER_SCENE: String = "res://scenes/player_scenes/player.tscn"
const MONSTER_SCENE: String = "res://scenes/monster_scenes/monster.tscn"

## 旧 C# 相克矩阵的攻击/防御属性对（按 ElementType 整数编码）。
const COUNTER_PAIRS: Array[Vector2i] = [
	Vector2i(2, 1),
	Vector2i(1, 4),
	Vector2i(4, 3),
	Vector2i(3, 5),
	Vector2i(5, 2),
]
## 旧 C# 被克制矩阵的攻击/防御属性对（按 ElementType 整数编码）。
const RESIST_PAIRS: Array[Vector2i] = [
	Vector2i(1, 2),
	Vector2i(3, 4),
	Vector2i(5, 3),
	Vector2i(4, 1),
	Vector2i(2, 5),
]


## 返回 GodotAI 使用的稳定套件名称。
##
## @return 伤害接收组件契约套件名。
func suite_name() -> String:
	return "damage_receiver_contract"


## 验证三个生产脚本存在、基类型正确且不声明 class_name。
func test_production_scripts_exist_with_expected_bases() -> void:
	for path: String in [DAMAGE_RECEIVER_GD, DAMAGE_FORMULA_GD, ELEMENTAL_SYSTEM_GD]:
		assert_true(FileAccess.file_exists(path), "生产脚本必须存在：%s" % path)

	var receiver: String = FileAccess.get_file_as_string(DAMAGE_RECEIVER_GD)
	assert_true(receiver.begins_with("extends Node"), "伤害接收组件必须直接继承 Node。")
	assert_true(receiver.contains("signal DamageResolved("), "必须保留同名 DamageResolved 信号。")
	assert_true(
		receiver.contains(
			"const RESULT_SCRIPT_PATH: String = \"res://core/combat/damage_resolution_result.gd\""
		),
		"结算结果必须切到 GDScript 生产 DTO 路径。"
	)
	assert_true(receiver.contains("load(RESULT_SCRIPT_PATH)"), "结算结果必须按路径加载 DTO 脚本。")

	for path: String in [DAMAGE_FORMULA_GD, ELEMENTAL_SYSTEM_GD]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_true(text.begins_with("extends RefCounted"), "纯计算脚本必须继承 RefCounted：%s" % path)

	for path: String in [DAMAGE_RECEIVER_GD, DAMAGE_FORMULA_GD, ELEMENTAL_SYSTEM_GD]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_false(_declares_class_name(text), "生产脚本不得声明 class_name：%s" % path)
		assert_false(text.contains("TODO"), "生产脚本不得保留 TODO 占位：%s" % path)


## 验证生产脚本保留旧 C# 的公开方法面与导出属性默认值。
func test_production_receiver_keeps_legacy_surface() -> void:
	var text: String = FileAccess.get_file_as_string(DAMAGE_RECEIVER_GD)

	assert_true(text.contains("func ReceiveDamage(payload: Variant)"), "必须保留 ReceiveDamage 方法名。")
	assert_true(text.contains("@export var RandomVarianceMin: float = 0.95"), "随机浮动下限默认值必须保持 0.95。")
	assert_true(text.contains("@export var RandomVarianceMax: float = 1.05"), "随机浮动上限默认值必须保持 1.05。")
	assert_true(text.contains("func _ready() -> void:"), "必须保留进入场景树时随机化随机源的时机。")
	assert_true(text.contains("_rng.randomize()"), "随机源必须随机化，等价旧 C# _Ready。")
	assert_true(
		text.contains("push_error(\"DamageReceiverComponent received null damage payload.\")"),
		"空载荷诊断文本必须与旧 C# 一致。"
	)
	assert_true(
		text.contains("push_error(\"DamageReceiverComponent has no parent defender.\")"),
		"缺失防御方诊断文本必须与旧 C# 一致。"
	)
	assert_true(
		text.contains("find_component(source, ATTRIBUTE_COMPONENT_NAME)")
		or text.contains("_find_component(source, ATTRIBUTE_COMPONENT_NAME)"),
		"必须按节点名查找攻击方属性组件。"
	)


## 验证伤害公式与旧 C# 的数值语义逐项等价。
func test_damage_formula_matches_legacy_semantics() -> void:
	var formula: GDScript = load(DAMAGE_FORMULA_GD)
	assert_true(formula != null, "伤害公式脚本必须可加载。")

	# C# 对照部分：垫片退役后整段退场，下面的 GDScript 断言仍照跑。
	var constants: String = CS_OPTIONAL.read(COMBAT_CONSTANTS_CS)
	if not constants.is_empty():
		assert_true(
			constants.contains("DamageFormulaConstant = 100f"),
			"伤害公式常数评审点：旧 C# 必须仍是 100f。"
		)
	assert_true(
		FileAccess.get_file_as_string(DAMAGE_FORMULA_GD).contains(
			"const DAMAGE_FORMULA_CONSTANT: float = 100.0"
		),
		"GDScript 公式常数必须与旧 C# 一致。"
	)

	assert_true(
		is_equal_approx(formula.CalculatePhysicalBaseDamage(100.0, 100.0, 100.0, 0.0, 0.0), 100.0),
		"同攻同防时物理基础伤害应等于技能威力。"
	)
	assert_true(
		is_equal_approx(formula.CalculatePhysicalBaseDamage(100.0, 100.0, 100.0, 0.5, 0.0), 100.0 * 200.0 / 150.0),
		"50% 物穿应把有效抗性降到 50 并进入攻防比值。"
	)
	assert_true(
		is_equal_approx(formula.CalculateMagicBaseDamage(50.0, 100.0, 100.0, 0.0, 0.0), 50.0),
		"法术公式必须与物理公式共用同一比值结构。"
	)
	assert_true(
		is_equal_approx(formula.CalculateEffectiveResistance(-10.0, 2.0, -5.0), 0.0),
		"负抗性、超额穿透率与负固定穿透都必须归一到 0。"
	)
	assert_true(
		is_equal_approx(formula.CalculateEffectiveResistance(200.0, 1.0, 50.0), 0.0),
		"穿透率上限 1 与固定穿透叠加后有效抗性不得为负。"
	)

	assert_false(formula.ShouldEvade(0.0, 0.0), "闪避率 0 不得触发闪避。")
	assert_false(formula.ShouldEvade(1.0, 1.0), "随机值 1 不得触发闪避。")
	assert_true(formula.ShouldEvade(1.0, 0.5), "满闪避率必须触发闪避。")
	assert_false(formula.ShouldCrit(0.0, 0.0), "暴击率 0 不得触发暴击。")
	assert_true(formula.ShouldCrit(1.0, 0.5), "满暴击率必须触发暴击。")

	assert_true(is_equal_approx(formula.CalculateCriticalModifier(true, 3.0), 3.0), "暴击倍率应原样生效。")
	assert_true(is_equal_approx(formula.CalculateCriticalModifier(true, 0.5), 1.0), "暴击倍率低于 1 时按 1 处理。")
	assert_true(is_equal_approx(formula.CalculateCriticalModifier(false, 3.0), 1.0), "非暴击必须返回 1。")

	assert_true(is_equal_approx(formula.CalculateRandomVariance(2.0, 2.0, 0.0), 2.0), "上下限相同时浮动倍率固定。")
	assert_true(is_equal_approx(formula.CalculateRandomVariance(1.0, 3.0, 0.0), 1.0), "浮动下限应落在最小侧。")
	assert_true(is_equal_approx(formula.CalculateRandomVariance(3.0, 1.0, 0.0), 1.0), "上下限反转时必须先归一化到较小侧。")
	assert_true(is_equal_approx(formula.CalculateRandomVariance(3.0, 1.0, 1.0), 3.0), "上下限反转后滚动到上限时返回较大值。")

	assert_eq(formula.CalculateActualDamage(10, 5), 5, "实际扣血不得超过防御方当前生命。")
	assert_eq(formula.CalculateActualDamage(-10, 5), 0, "负伤害必须归零。")
	assert_eq(formula.CalculateLifestealAmount(10, 0.25), 3, "吸血量必须按远离零舍入 2.5 -> 3。")
	assert_eq(formula.CalculateLifestealAmount(9, 0.5), 5, "吸血量必须按远离零舍入 4.5 -> 5。")
	assert_eq(formula.CalculateLifestealAmount(-10, 0.5), 0, "负伤害不得产生吸血量。")


## 验证五行矩阵与旧 C# 的十个属性对逐项等价。
func test_elemental_matrix_matches_legacy_semantics() -> void:
	var elemental: GDScript = load(ELEMENTAL_SYSTEM_GD)
	assert_true(elemental != null, "五行脚本必须可加载。")

	var csharp: String = CS_OPTIONAL.read(ELEMENTAL_SYSTEM_CS)
	var gd_text: String = FileAccess.get_file_as_string(ELEMENTAL_SYSTEM_GD)
	assert_true(gd_text.contains("const COUNTER_MODIFIER: float = 1.5"), "相克倍率必须保持 1.5。")
	assert_true(gd_text.contains("const RESIST_MODIFIER: float = 0.5"), "被克制倍率必须保持 0.5。")

	var element_names: Array[String] = _read_csharp_enum_members_named(ELEMENT_TYPE_CS, "ElementType")
	if element_names.is_empty():
		# C# 退役后没有枚举名对照源：保留 GDScript 侧的既有断言即可。
		assert_true(is_equal_approx(elemental.CalculateMultiplier(0, 3), 1.0), "无属性攻击不得产生克制倍率。")
		assert_true(is_equal_approx(elemental.CalculateMultiplier(3, 3), 1.0), "同属性不得产生克制倍率。")
		assert_true(is_equal_approx(elemental.CalculateMultiplier(1, 5), 1.0), "无克制关系必须返回 1.0。")
		return
	assert_eq(element_names.size(), 6, "旧 C# ElementType 成员数必须仍是 6。")

	for pair: Vector2i in COUNTER_PAIRS:
		var attack: int = pair.x
		var defense: int = pair.y
		assert_true(
			is_equal_approx(elemental.CalculateMultiplier(attack, defense), 1.5),
			"相克对必须保持 1.5 倍：%s -> %s" % [element_names[attack], element_names[defense]]
		)
		assert_true(
			csharp.contains(
				"{(ElementType.%s, ElementType.%s), COUNTERMODIFIER}"
				% [element_names[attack], element_names[defense]]
			),
			"旧 C# 相克矩阵必须仍声明该属性对：%s -> %s"
			% [element_names[attack], element_names[defense]]
		)

	for pair: Vector2i in RESIST_PAIRS:
		var attack: int = pair.x
		var defense: int = pair.y
		assert_true(
			is_equal_approx(elemental.CalculateMultiplier(attack, defense), 0.5),
			"被克制对必须保持 0.5 倍：%s -> %s" % [element_names[attack], element_names[defense]]
		)
		assert_true(
			csharp.contains(
				"{(ElementType.%s, ElementType.%s), RESISTMODIFIER}"
				% [element_names[attack], element_names[defense]]
			),
			"旧 C# 被克制矩阵必须仍声明该属性对：%s -> %s"
			% [element_names[attack], element_names[defense]]
		)

	assert_true(is_equal_approx(elemental.CalculateMultiplier(0, 3), 1.0), "无属性攻击不得产生克制倍率。")
	assert_true(is_equal_approx(elemental.CalculateMultiplier(3, 3), 1.0), "同属性不得产生克制倍率。")
	assert_true(is_equal_approx(elemental.CalculateMultiplier(1, 5), 1.0), "无克制关系必须返回 1.0。")


## 验证枚举名称表与修饰位常量与旧 C# 同步，保证日志文本不漂移。
func test_enum_names_and_modifier_flags_match_legacy_csharp() -> void:
	var text: String = FileAccess.get_file_as_string(DAMAGE_RECEIVER_GD)

	# C# 退役后没有枚举名对照源：本用例的 C# 侧断言整体退场。
	if not CS_OPTIONAL.present_all([ELEMENT_TYPE_CS, DAMAGE_PAYLOAD_CS]):
		assert_false(text.contains("TODO"), "伤害接收组件不得保留 TODO 占位。")
		return
	var element_line: String = _find_line(text, "const ELEMENT_NAMES")
	var element_members: Array[String] = _read_csharp_enum_members_named(ELEMENT_TYPE_CS, "ElementType")
	var last_element_index: int = -1
	for member: String in element_members:
		var index: int = element_line.find("\"%s\"" % member)
		assert_true(index > last_element_index, "五行名称表必须与旧 C# 枚举顺序一致：%s" % member)
		last_element_index = index

	var type_line: String = _find_line(text, "const DAMAGE_TYPE_NAMES")
	var type_members: Array[String] = _read_csharp_enum_members_named(DAMAGE_PAYLOAD_CS, "DamageType")
	assert_eq(type_members.size(), 3, "旧 C# DamageType 成员数必须仍是 3。")
	var last_type_index: int = -1
	for member: String in type_members:
		var index: int = type_line.find("\"%s\"" % member)
		assert_true(index > last_type_index, "伤害类型名称表必须与旧 C# 枚举顺序一致：%s" % member)
		last_type_index = index

	var type_values: Array[int] = _read_const_values(text, "DAMAGE_TYPE_")
	assert_eq(type_values.size(), type_members.size(), "伤害类型常量数量必须与旧 C# 枚举一致。")
	for index in range(type_values.size()):
		assert_eq(type_values[index], index, "伤害类型常量必须与旧 C# 枚举顺序一致。")

	var payload: String = FileAccess.get_file_as_string(DAMAGE_PAYLOAD_CS)
	var expected_flags: Dictionary = {
		"Evasion": 1,
		"Critical": 2,
		"RandomVariance": 4,
		"Lifesteal": 8,
	}
	var flag_values: Array[int] = _read_const_values(text, "MODIFIER_")
	assert_eq(flag_values.size(), 4, "伤害修饰位常量数量必须仍是 4。")
	var flag_names: Array[String] = ["Evasion", "Critical", "RandomVariance", "Lifesteal"]
	for index in range(flag_values.size()):
		var flag_name: String = flag_names[index]
		assert_eq(flag_values[index], expected_flags[flag_name], "修饰位必须保持旧 C# 位值：%s" % flag_name)
		assert_true(
			payload.contains("%s = 1 << %d" % [flag_name, index]),
			"旧 C# DamageModifierFlags 必须仍声明该位：%s" % flag_name
		)
	assert_true(
		payload.contains("DefaultCombat = Evasion | Critical | RandomVariance | Lifesteal"),
		"普通攻击默认修饰集合必须保持不变。"
	)


## 验证两个实体场景已把伤害接收组件脚本切换为 GDScript 并保持 uid 一致。
func test_scenes_switched_to_gdscript() -> void:
	var expected_uid: String = FileAccess.get_file_as_string(DAMAGE_RECEIVER_UID_PATH).strip_edges()
	assert_true(expected_uid.begins_with("uid://"), "伤害接收组件生产脚本必须带 uid 旁车。")

	for scene_path: String in [PLAYER_SCENE, MONSTER_SCENE]:
		var text: String = FileAccess.get_file_as_string(scene_path)
		assert_true(
			text.contains('path="res://entities/components/damage_receiver_component.gd"'),
			"场景必须引用 GDScript 伤害接收组件：%s" % scene_path
		)
		assert_true(text.contains('uid="%s"' % expected_uid), "场景必须使用生产脚本 uid：%s" % scene_path)
		assert_false(text.contains("DamageReceiverComponent.cs"), "场景不得再引用旧 C# 组件：%s" % scene_path)
		assert_false(text.contains("uid://delpo10ufxcco"), "场景不得再引用旧 C# 组件 uid：%s" % scene_path)


## 验证 C# 消费者改为按方法协议访问伤害接收组件。
func test_csharp_consumers_use_method_protocol() -> void:
	if not CS_OPTIONAL.present_all([DAMAGE_EFFECT_CS, BURN_STATUS_INSTANCE_CS]):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var damage_effect: String = FileAccess.get_file_as_string(DAMAGE_EFFECT_CS)
	assert_true(
		damage_effect.contains('GetNodeOrNull<Node>("Components/DamageReceiverComponent")'),
		"伤害效果必须按通用 Node 获取伤害接收组件。"
	)
	assert_false(
		damage_effect.contains("<DamageReceiverComponent>"),
		"伤害效果不得再持有强类型伤害接收组件边界。"
	)

	var burn: String = FileAccess.get_file_as_string(BURN_STATUS_INSTANCE_CS)
	assert_true(
		burn.contains('GetNodeOrNull<Node>("Components/DamageReceiverComponent")'),
		"灼烧状态必须按通用 Node 获取伤害接收组件。"
	)
	assert_true(burn.contains('Call("ReceiveDamage"'), "灼烧状态必须按方法协议提交伤害载荷。")
	assert_false(burn.contains("<DamageReceiverComponent>"), "灼烧状态不得再持有强类型伤害接收组件边界。")


## 验证旧 C# 垫片仍保留完整实现，未用空实现替代。
func test_legacy_shim_keeps_full_implementation() -> void:
	if not CS_OPTIONAL.present(DAMAGE_RECEIVER_CS):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	assert_true(FileAccess.file_exists(DAMAGE_RECEIVER_CS), "旧 C# 垫片必须保留到全量迁移完成。")
	var shim: String = FileAccess.get_file_as_string(DAMAGE_RECEIVER_CS)

	assert_true(shim.contains("public partial class DamageReceiverComponent : Node"), "旧 C# 类必须仍然存在。")
	assert_true(shim.contains("DamageFormula.CalculatePhysicalBaseDamage"), "垫片必须保留物理公式调用。")
	assert_true(shim.contains("DamageFormula.CalculateMagicBaseDamage"), "垫片必须保留法术公式调用。")
	assert_true(shim.contains("ElementalSystem.CalculateMultiplier"), "垫片必须保留五行克制调用。")
	assert_true(
		shim.contains("MonsterDataProtocol.ReadElementalProperty"),
		"垫片必须保留跨语言怪物属性读取。"
	)
	for method_name: String in [
		'"ApplyModifyOutgoingDamage"',
		'"ApplyModifyIncomingDamageBeforeMitigation"',
		'"ApplyModifyIncomingDamageAfterMitigation"',
		'"ApplyBeforeHealthDamage"',
	]:
		assert_true(shim.contains(method_name), "垫片必须保留状态伤害修正入口：%s" % method_name)


## 验证 GDScript 结算顺序与旧 C# 逐行一致。
func test_settlement_order_matches_legacy() -> void:
	var text: String = FileAccess.get_file_as_string(DAMAGE_RECEIVER_GD)
	var ordered_markers: Array[String] = [
		"_has_damage_modifier(payload, MODIFIER_EVASION)",
		"var damage: float = _calculate_base_damage(payload, attacker_stats, defender_stats)",
		"_has_damage_modifier(payload, MODIFIER_CRITICAL)",
		"\"ApplyModifyOutgoingDamage\"",
		"\"ApplyModifyIncomingDamageBeforeMitigation\"",
		"damage = _apply_element_multiplier(payload, defender_root, damage)",
		"\"ApplyModifyIncomingDamageAfterMitigation\"",
		"var pre_guard_damage: int = maxi(0, roundi(damage))",
		"\"ApplyBeforeHealthDamage\"",
		"damage = _apply_random_variance(damage)",
		"defender_health.call(\"TakeDamage\", final_damage",
		"_apply_lifesteal(source, attacker_stats, actual_damage)",
	]

	var previous_index: int = -1
	for marker: String in ordered_markers:
		var index: int = text.find(marker)
		assert_true(index > previous_index, "结算顺序必须保持旧 C# 语义：%s" % marker)
		previous_index = index

	assert_true(text.contains("is_lethal: bool = actual_damage > 0"), "致死判定必须发生在实际扣血之后。")
	assert_true(
		text.contains("_read_vital_current_value(defender_health) <= 0"),
		"致死判定必须读取跨语言生命组件当前值。"
	)
	assert_true(
		text.contains("[Damage] Target: %s | Source: %s | Damage: 0 | Evaded: True | Element: %s | Type: %s"),
		"闪避日志必须在排除暴击与吸血后返回，且文本保持旧格式。"
	)
	assert_true(
		text.contains("Critical: %s"),
		"伤害日志必须保留暴击字段。"
	)
	assert_true(
		text.contains("func _bool_text(value: bool) -> String:"),
		"布尔日志必须格式化为旧 C# 的 True/False 文本。"
	)


## 判断脚本全文是否声明了 class_name。
##
## @param text GDScript 全文。
## @return 声明了 class_name 时返回 true。
func _declares_class_name(text: String) -> bool:
	for raw_line: String in text.split("\n"):
		if raw_line.strip_edges().begins_with("class_name"):
			return true

	return false


## 读取以指定前缀开头的常量声明行。
##
## @param text GDScript 全文。
## @param prefix 常量声明前缀，例如 "const ELEMENT_NAMES"。
## @return 第一个匹配的声明行；未找到时返回空字符串。
func _find_line(text: String, prefix: String) -> String:
	for raw_line: String in text.split("\n"):
		if raw_line.strip_edges().begins_with(prefix):
			return raw_line.strip_edges()

	return ""


## 读取指定 C# 枚举的成员名（按声明顺序）。
##
## @param path 旧 C# 脚本的 res:// 路径。
## @param enum_name 枚举名。
## @return 枚举成员名数组；无法识别时返回空数组。
func _read_csharp_enum_members_named(path: String, enum_name: String) -> Array[String]:
	var members: Array[String] = []
	var inside_enum := false

	if not FileAccess.file_exists(path):
		return members
	for raw_line: String in FileAccess.get_file_as_string(path).split("\n"):
		var line: String = raw_line.strip_edges()

		if not inside_enum:
			# 旧 C# 枚举把 { 写在下一行，因此只按声明行进入枚举体，再跳过花括号行。
			inside_enum = line.begins_with("public enum %s" % enum_name)
			continue

		if line == "{":
			continue

		if line.begins_with("}"):
			break

		if line.is_empty() or line.begins_with("//"):
			continue

		members.append(line.split("=")[0].strip_edges().trim_suffix(","))

	return members


## 读取 GDScript 生产脚本里以指定前缀开头的整数常量值（按声明顺序）。
##
## @param text GDScript 生产脚本全文。
## @param prefix 常量名前缀，例如 "MODIFIER_"。
## @return 常量值数组。
func _read_const_values(text: String, prefix: String) -> Array[int]:
	var values: Array[int] = []
	var needle := "const %s" % prefix

	for raw_line: String in text.split("\n"):
		var line: String = raw_line.strip_edges()

		if not line.begins_with(needle):
			continue

		# 只统计整数常量，避免同前缀的数组或浮点常量被误读。
		if not line.contains(": int = "):
			continue

		var value_text := line.split("=")[-1].strip_edges()
		values.append(int(value_text))

	return values


## 验证伤害结算结果切到 GDScript 生产实现，且护盾与上限数据经载荷字段协议跨语言读取。
##
## @return 无返回值。
func test_result_dto_migrated_to_gdscript_with_payload_protocol() -> void:
	assert_true(FileAccess.file_exists(DAMAGE_RESULT_GD), "结算结果生产脚本必须存在。")
	var text: String = FileAccess.get_file_as_string(DAMAGE_RESULT_GD)
	assert_true(text.begins_with("extends RefCounted"), "结算结果必须与旧 C# 同为 RefCounted。")
	assert_false(_declares_class_name(text), "结算结果不得声明 class_name。")

	for field: String in [
		"var Source: Node",
		"var Target: Node",
		"var RequestedDamage: int",
		"var PreGuardDamage: int",
		"var ActualDamage: int",
		"var Type: int",
		"var Element: int",
		"var IsEvaded: bool",
		"var IsCritical: bool",
		"var IsLethal: bool",
		"var ShieldAbsorbedDamage: int",
		"var ShieldWasBroken: bool",
		"var WasCapped: bool",
		"var HitIndex: int",
		"var HitCount: int",
		"var TargetRoleId: int",
	]:
		assert_true(text.contains(field), "结算结果必须保留旧 C# 字段：%s" % field)

	assert_true(text.contains("func GetFeedbackInt(property_name: String) -> int"), "必须保留 GetFeedbackInt 协议。")
	assert_true(text.contains("func GetFeedbackBool(property_name: String) -> bool"), "必须保留 GetFeedbackBool 协议。")
	assert_true(text.contains("func GetFeedbackNode(property_name: String) -> Node"), "必须保留 GetFeedbackNode 协议。")

	# 旧 C# 垫片与其内部追踪对象必须保留：C# 测试工程仍按旧类型消费。
	# C# 对照部分：垫片退役后整段退场，上面的 GDScript 断言仍照跑。
	if CS_OPTIONAL.present(DAMAGE_RESULT_CS):
		assert_true(FileAccess.file_exists(DAMAGE_RESULT_CS), "旧 C# 结算结果垫片必须保留。")
	var payload_text: String = CS_OPTIONAL.read(DAMAGE_PAYLOAD_CS)
	if not payload_text.is_empty():
		assert_true(
			payload_text.contains("public int ShieldAbsorbedDamage => ResolutionTrace.ShieldAbsorbedDamage;"),
			"载荷必须转发护盾吸收量。"
		)
		assert_true(
			payload_text.contains("public bool ShieldWasBroken => ResolutionTrace.ShieldWasBroken;"),
			"载荷必须转发护盾击破标记。"
		)
		assert_true(
			payload_text.contains("public int CappedDamage => ResolutionTrace.CappedDamage;"),
			"载荷必须转发单次扣血上限削减量。"
		)

	# 空载荷兜底：与旧 C# 的 payload?.X ?? 默认值 逐字一致。
	var result_script: GDScript = load(DAMAGE_RESULT_GD)
	assert_true(result_script != null, "结算结果脚本必须可加载。")
	var empty_result: RefCounted = result_script.new(null, -5, -3, true, false, true)
	assert_true(empty_result != null, "空载荷也必须能构造结算结果。")
	assert_eq(int(empty_result.get("PreGuardDamage")), 0, "负的候选伤害必须归零。")
	assert_eq(int(empty_result.get("ActualDamage")), 0, "负的实际伤害必须归零。")
	assert_eq(int(empty_result.get("HitCount")), 1, "空载荷的段数必须兜底为 1。")
	assert_eq(int(empty_result.get("ShieldAbsorbedDamage")), 0, "空载荷的护盾吸收量必须为 0。")
	assert_eq(int(empty_result.call("GetFeedbackInt", "ActualDamage")), 0, "GetFeedbackInt 必须返回实际伤害。")
	assert_true(bool(empty_result.call("GetFeedbackBool", "IsEvaded")), "GetFeedbackBool 必须返回闪避标记。")
	assert_true(empty_result.call("GetFeedbackNode", "Source") == null, "空载荷的来源必须为空。")

	# 真实 C# 载荷 → GDScript 结算结果：覆盖字段读取与护盾/上限转发协议。
	if not CS_OPTIONAL.present(DAMAGE_PAYLOAD_CS):
		return
	var payload_script: Script = load(DAMAGE_PAYLOAD_CS)
	assert_true(payload_script != null, "C# 载荷垫片必须可加载。")
	var payload: Object = payload_script.new()
	assert_true(payload != null, "C# 载荷垫片必须可实例化。")
	payload.set("Damage", 40)
	payload.set("Type", 1)
	payload.set("Element", 5)
	payload.set("HitIndex", 2)
	payload.set("HitCount", 3)
	payload.set("TargetRoleId", 4)
	payload.call("RecordShieldAbsorption", 12.4, true)
	payload.call("RecordDamageCap", 3.6)

	var result: RefCounted = result_script.new(payload, 40, 25, false, true, false)
	assert_eq(int(result.get("RequestedDamage")), 40, "载荷基础伤害必须原样读取。")
	assert_eq(int(result.get("Type")), 1, "载荷公式类型必须原样读取。")
	assert_eq(int(result.get("Element")), 5, "载荷五行必须原样读取。")
	assert_eq(int(result.get("ShieldAbsorbedDamage")), 12, "护盾吸收量必须经载荷协议四舍五入后读回。")
	assert_true(bool(result.get("ShieldWasBroken")), "护盾击破标记必须经载荷协议读回。")
	assert_true(bool(result.get("WasCapped")), "上限削减量大于 0 时必须标记 WasCapped。")
	assert_eq(int(result.get("HitIndex")), 2, "段索引必须原样读取。")
	assert_eq(int(result.get("HitCount")), 3, "段数必须原样读取。")
	assert_eq(int(result.get("TargetRoleId")), 4, "目标角色必须原样读取。")
	assert_eq(int(result.call("GetFeedbackInt", "ShieldAbsorbedDamage")), 12, "GetFeedbackInt 必须返回护盾吸收量。")
	assert_true(bool(result.call("GetFeedbackBool", "WasCapped")), "GetFeedbackBool 必须返回上限标记。")
	assert_true(result.call("GetFeedbackNode", "Target") == payload.get("Target"), "GetFeedbackNode 必须返回载荷目标。")


## 验证伤害载荷本体已迁移到 GDScript，且三个 GDScript 构造点都切到生产脚本。
##
## 载荷是伤害管线的跨语言信封：字段默认值与护盾/上限记录语义必须与旧 C# 逐字一致，
## 否则同一次伤害在两种载荷实现下会得出不同的结算结果。
func test_damage_payload_migrated_to_gdscript() -> void:
	assert_true(FileAccess.file_exists(DAMAGE_PAYLOAD_GD), "伤害载荷生产脚本必须存在。")
	var text: String = FileAccess.get_file_as_string(DAMAGE_PAYLOAD_GD)
	assert_true(text.begins_with("extends RefCounted"), "载荷必须继承 RefCounted 才能跨语言传递。")
	assert_false(_declares_class_name(text), "载荷不得声明 class_name。")
	assert_false(text.contains("TODO"), "载荷不得保留 TODO 占位。")

	for marker: String in [
		"var Source: Node = null",
		"var Target: Node = null",
		"var Damage: int = 0",
		"var DamageModifiers: int = MODIFIER_DEFAULT_COMBAT",
		"var IsExtraDamage: bool = false",
		"var HitCount: int = 1",
		"func HasDamageModifier(modifier: int) -> bool",
		"func RecordShieldAbsorption(absorbed_damage: float, was_broken: bool) -> void",
		"func RecordDamageCap(reduced_damage: float) -> void",
	]:
		assert_true(text.contains(marker), "载荷必须保留旧 C# 协议：%s" % marker)

	# 位标记与枚举取值必须与旧 C# DamageModifierFlags / DamageType 逐字一致。
	var payload_script: GDScript = load(DAMAGE_PAYLOAD_GD)
	assert_true(payload_script != null, "载荷生产脚本必须可加载。")
	var payload: RefCounted = payload_script.new()
	assert_true(payload != null, "载荷生产脚本必须可实例化。")

	assert_eq(int(payload.get("DamageModifiers")), 15, "默认修饰集合必须等于 Evasion|Critical|RandomVariance|Lifesteal。")
	assert_eq(int(payload.get("Type")), 0, "伤害类型默认值必须为 Physical。")
	assert_eq(int(payload.get("Element")), 0, "五行默认值必须为 None。")
	assert_eq(int(payload.get("HitIndex")), 0, "段索引默认值必须为 0。")
	assert_eq(int(payload.get("HitCount")), 1, "段数默认值必须为 1。")
	assert_eq(int(payload.get("TargetRoleId")), 0, "目标角色默认值必须为 0。")
	assert_false(bool(payload.get("IsExtraDamage")), "额外伤害标记默认值必须为 false。")
	assert_eq(int(payload.get("ShieldAbsorbedDamage")), 0, "护盾吸收量初始必须为 0。")
	assert_false(bool(payload.get("ShieldWasBroken")), "护盾击破标记初始必须为 false。")
	assert_eq(int(payload.get("CappedDamage")), 0, "上限削减量初始必须为 0。")

	assert_false(bool(payload.call("HasDamageModifier", 0)), "None 修饰恒为 false。")
	assert_true(bool(payload.call("HasDamageModifier", 1)), "默认集合必须启用闪避。")
	assert_true(bool(payload.call("HasDamageModifier", 8)), "默认集合必须启用吸血。")
	payload.set("DamageModifiers", 0)
	assert_false(bool(payload.call("HasDamageModifier", 1)), "清空修饰后不得再命中闪避。")
	payload.set("DamageModifiers", 15)

	# 护盾吸收：四舍五入累加；非正吸收量整条忽略（不更新击破标记）；击破标记只做或运算。
	payload.call("RecordShieldAbsorption", 12.4, true)
	assert_eq(int(payload.get("ShieldAbsorbedDamage")), 12, "护盾吸收量必须四舍五入后累加。")
	assert_true(bool(payload.get("ShieldWasBroken")), "击破标记必须被记录。")
	payload.call("RecordShieldAbsorption", 0.0, false)
	assert_eq(int(payload.get("ShieldAbsorbedDamage")), 12, "非正吸收量不得改变累加值。")
	assert_true(bool(payload.get("ShieldWasBroken")), "非正吸收量不得回退击破标记。")
	payload.call("RecordShieldAbsorption", 2.6, false)
	assert_eq(int(payload.get("ShieldAbsorbedDamage")), 15, "二次吸收必须继续累加。")

	payload.call("RecordDamageCap", 3.6)
	assert_eq(int(payload.get("CappedDamage")), 4, "上限削减量必须四舍五入后累加。")
	payload.call("RecordDamageCap", -5.0)
	assert_eq(int(payload.get("CappedDamage")), 4, "负的上限削减量必须归零后累加。")

	# GDScript 载荷 → GDScript 结算结果：字段与转发协议必须同样可读。
	payload.set("Damage", 40)
	payload.set("Type", 1)
	payload.set("Element", 5)
	payload.set("HitIndex", 2)
	payload.set("HitCount", 3)
	payload.set("TargetRoleId", 4)
	var result_script: GDScript = load(DAMAGE_RESULT_GD)
	var result: RefCounted = result_script.new(payload, 40, 25, false, true, false)
	assert_eq(int(result.get("RequestedDamage")), 40, "GDScript 载荷基础伤害必须原样读取。")
	assert_eq(int(result.get("HitIndex")), 2, "GDScript 载荷段索引必须原样读取。")
	assert_eq(int(result.get("ShieldAbsorbedDamage")), 15, "GDScript 载荷护盾吸收量必须经协议读回。")
	assert_true(bool(result.get("ShieldWasBroken")), "GDScript 载荷击破标记必须经协议读回。")
	assert_true(bool(result.get("WasCapped")), "GDScript 载荷上限削减必须标记 WasCapped。")
	# GetFeedbackInt 的支持名单与旧 C# 逐字一致（不含 CappedDamage），因此这里读候选伤害。
	assert_eq(int(result.call("GetFeedbackInt", "PreGuardDamage")), 40, "GetFeedbackInt 必须返回候选伤害。")
	# 结算结果与旧 C# 一样只暴露 WasCapped，上限削减量本身留在载荷上。
	assert_eq(int(payload.get("CappedDamage")), 4, "GDScript 载荷必须保留上限削减量。")

	# 三个 GDScript 构造点必须切到生产载荷，旧 C# 路径只允许留在注释与测试基线里。
	for consumer_path: String in [
		"res://core/combat/effects/damage_effect.gd",
		"res://core/combat/buffs/burn_status_instance.gd",
		"res://scripts/battle_scripts/battle_manager.gd",
	]:
		var consumer: String = FileAccess.get_file_as_string(consumer_path)
		assert_true(
			consumer.contains('"res://core/combat/damage_payload.gd"'),
			"GDScript 构造点必须切到生产载荷：%s" % consumer_path
		)
		assert_false(
			consumer.contains('load(DAMAGE_PAYLOAD_SCRIPT_PATH)') and consumer.contains("DamagePayload.cs"),
			"GDScript 构造点不得再加载旧 C# 载荷：%s" % consumer_path
		)

	# 旧 C# 载荷垫片必须完整保留（C# 测试工程与 C# 状态 Hook 仍按旧类型消费）。
	if CS_OPTIONAL.present(DAMAGE_PAYLOAD_CS):
		assert_true(FileAccess.file_exists(DAMAGE_PAYLOAD_CS), "旧 C# 载荷垫片必须保留。")
