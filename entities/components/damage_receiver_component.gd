extends Node

## 伤害接收组件的 GDScript 生产实现，等价旧 entities/components/DamageReceiverComponent.cs。
##
## 结算顺序与旧 C# 完全一致：闪避 → 基础公式 → 暴击 → 状态输出修正 → 状态减伤前修正
## → 五行克制 → 状态减伤后修正 → 状态扣血前修正 → 随机浮动 → 生命扣除 → 吸血。
## 组件按节点名查找同级组件，属性与生命数值通过字段/方法协议读取，
## 因此同一份实现可以同时对接仍在 C# 中的属性组件与已经迁移的 GDScript 组件。
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。


## 一次伤害完成所有公式、状态和生命扣除后发出。
## 结果只用于表现和日志，不允许监听方修改已经完成的战斗状态。
signal DamageResolved(result)

## 结算结果的 GDScript 生产脚本路径；旧 C# DamageResolutionResult.cs 保留为兼容垫片与 C# 测试基线。
## 护盾吸收与单次扣血上限经载荷的转发字段协议读取（DamageResolutionTrace 是非 Godot 的纯 CLR 类）。
const RESULT_SCRIPT_PATH: String = "res://core/combat/damage_resolution_result.gd"
## 伤害基础公式的 GDScript 实现。
const DAMAGE_FORMULA_SCRIPT: GDScript = preload("res://core/combat/damage_formula.gd")
## 五行克制与天气修正的 GDScript 实现。
const ELEMENTAL_SYSTEM_SCRIPT: GDScript = preload("res://core/combat/elemental_system.gd")

## 属性组件节点名。
const ATTRIBUTE_COMPONENT_NAME: String = "AttributeComponent"
## 状态组件节点名。
const STATUS_COMPONENT_NAME: String = "StatusComponent"
## 生命组件节点名。
const HEALTH_COMPONENT_NAME: String = "HealthComponent"

## DamageModifierFlags.Evasion。
const MODIFIER_EVASION: int = 1
## DamageModifierFlags.Critical。
const MODIFIER_CRITICAL: int = 2
## DamageModifierFlags.RandomVariance。
const MODIFIER_RANDOM_VARIANCE: int = 4
## DamageModifierFlags.Lifesteal。
const MODIFIER_LIFESTEAL: int = 8

## DamageType.Physical。
const DAMAGE_TYPE_PHYSICAL: int = 0
## DamageType.Magic。
const DAMAGE_TYPE_MAGIC: int = 1
## DamageType.Real。
const DAMAGE_TYPE_REAL: int = 2

## 五行属性名称，仅用于保持与旧 C# 枚举字符串完全一致的日志文本。
const ELEMENT_NAMES: Array[String] = ["None", "Wood", "Metal", "Water", "Earth", "Fire"]
## 伤害类型名称，仅用于保持与旧 C# 枚举字符串完全一致的日志文本。
const DAMAGE_TYPE_NAMES: Array[String] = ["Physical", "Magic", "Real"]

## 随机浮动下限，等价旧 C# 导出属性 RandomVarianceMin。
@export var RandomVarianceMin: float = 0.95
## 随机浮动上限，等价旧 C# 导出属性 RandomVarianceMax。
@export var RandomVarianceMax: float = 1.05

## 命中随机源，等价旧 C# 的 RandomNumberGenerator。
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## 组件进入场景树时随机化随机源，与旧 C# _Ready 一致。
##
## @return 无返回值。
func _ready() -> void:
	_rng.randomize()


## 接收伤害载荷，按载荷配置结算闪避、暴击、属性克制、随机浮动和吸血。
##
## @param payload 伤害来源、目标、技能威力、伤害类型、五行属性和修饰配置。
## @return 已完成的伤害结算结果；配置异常时返回不产生生命变化的结果。
func ReceiveDamage(payload: Variant) -> Variant:
	if payload == null:
		push_error("DamageReceiverComponent received null damage payload.")
		return _new_result(null, 0, 0, false, false, false)

	var defender_components: Node = get_parent()
	var target: Node = _read_node(payload, "Target")
	var defender_root: Node = target
	if defender_root == null and defender_components != null:
		defender_root = defender_components.get_parent()
	if defender_root == null:
		defender_root = defender_components

	if defender_components == null:
		push_error("DamageReceiverComponent has no parent defender.")
		return _new_result(payload, 0, 0, false, false, false)

	var source: Node = _read_node(payload, "Source")
	var attacker_stats: Node = _find_component(source, ATTRIBUTE_COMPONENT_NAME)
	var defender_stats: Node = _find_component(defender_root, ATTRIBUTE_COMPONENT_NAME)
	if defender_stats == null:
		defender_stats = defender_components.get_node_or_null(ATTRIBUTE_COMPONENT_NAME)

	# 状态组件已迁移到 GDScript，这里只按节点名查找并按非 ref 包装方法协议调用。
	var attacker_status: Node = _find_component(source, STATUS_COMPONENT_NAME)
	var defender_status: Node = _find_component(defender_root, STATUS_COMPONENT_NAME)
	if defender_status == null:
		defender_status = defender_components.get_node_or_null(STATUS_COMPONENT_NAME)

	if (
		_has_damage_modifier(payload, MODIFIER_EVASION)
		and DAMAGE_FORMULA_SCRIPT.ShouldEvade(
			_read_attribute(defender_stats, "EvasionRate", 0.0),
			_rng.randf()
		)
	):
		var evaded_result: Variant = _new_result(payload, 0, 0, true, false, false)
		DamageResolved.emit(evaded_result)
		print(
			"[Damage] Target: %s | Source: %s | Damage: 0 | Evaded: True | Element: %s | Type: %s"
			% [
				_entity_name(defender_root, defender_components),
				_source_name(source),
				_element_name(payload),
				_damage_type_name(payload),
			]
		)
		return evaded_result

	var damage: float = _calculate_base_damage(payload, attacker_stats, defender_stats)
	var is_critical: bool = false
	if _has_damage_modifier(payload, MODIFIER_CRITICAL):
		is_critical = DAMAGE_FORMULA_SCRIPT.ShouldCrit(
			_read_attribute(attacker_stats, "CritRate", 0.0),
			_rng.randf()
		)
		damage *= DAMAGE_FORMULA_SCRIPT.CalculateCriticalModifier(
			is_critical,
			_read_attribute(attacker_stats, "CritDamage", 1.0)
		)

	damage = _apply_status_damage_modifier(
		attacker_status,
		"ApplyModifyOutgoingDamage",
		payload,
		damage
	)
	damage = _apply_status_damage_modifier(
		defender_status,
		"ApplyModifyIncomingDamageBeforeMitigation",
		payload,
		damage
	)

	damage = _apply_element_multiplier(payload, defender_root, damage)

	damage = _apply_status_damage_modifier(
		defender_status,
		"ApplyModifyIncomingDamageAfterMitigation",
		payload,
		damage
	)
	var pre_guard_damage: int = maxi(0, roundi(damage))
	damage = _apply_status_damage_modifier(
		defender_status,
		"ApplyBeforeHealthDamage",
		payload,
		damage
	)
	if _has_damage_modifier(payload, MODIFIER_RANDOM_VARIANCE):
		damage = _apply_random_variance(damage)

	var final_damage: int = maxi(0, roundi(damage))
	# 生命组件已迁移到 GDScript；这里只按 TakeDamage 方法协议与 CurrentValue 属性读取。
	var defender_health: Node = _find_component(defender_root, HEALTH_COMPONENT_NAME)
	if defender_health == null:
		defender_health = defender_components.get_node_or_null(HEALTH_COMPONENT_NAME)

	var actual_damage: int = 0
	if defender_health != null:
		actual_damage = int(
			defender_health.call("TakeDamage", final_damage, _read_int(payload, "Element"))
		)

	if _has_damage_modifier(payload, MODIFIER_LIFESTEAL):
		_apply_lifesteal(source, attacker_stats, actual_damage)

	var is_lethal: bool = actual_damage > 0 and _read_vital_current_value(defender_health) <= 0
	var result: Variant = _new_result(
		payload,
		pre_guard_damage,
		actual_damage,
		false,
		is_critical,
		is_lethal
	)
	DamageResolved.emit(result)

	print(
		"[Damage] Target: %s | Source: %s | Damage: %d | Critical: %s | Element: %s | Type: %s"
		% [
			_entity_name(defender_root, defender_components),
			_source_name(source),
			actual_damage,
			_bool_text(is_critical),
			_element_name(payload),
			_damage_type_name(payload),
		]
	)
	return result


## 按伤害类型计算基础伤害，真实伤害直接使用技能威力。
##
## @param payload 本次伤害载荷。
## @param attacker_stats 攻击方属性组件；为空时攻击属性按 0 处理。
## @param defender_stats 防御方属性组件；为空时防御属性按 0 处理。
## @return 返回套用攻防比值后的基础伤害。
func _calculate_base_damage(payload: Variant, attacker_stats: Node, defender_stats: Node) -> float:
	var skill_power: float = maxf(0.0, _read_float(payload, "Damage"))
	var damage_type: int = _read_int(payload, "Type")

	if damage_type == DAMAGE_TYPE_PHYSICAL:
		return DAMAGE_FORMULA_SCRIPT.CalculatePhysicalBaseDamage(
			skill_power,
			_read_attribute(attacker_stats, "PhysAtk", 0.0),
			_read_attribute(defender_stats, "PhysDef", 0.0),
			_read_attribute(attacker_stats, "PhysPenetrationRate", 0.0),
			_read_attribute(attacker_stats, "FixedPhysPenetration", 0.0)
		)

	if damage_type == DAMAGE_TYPE_MAGIC:
		return DAMAGE_FORMULA_SCRIPT.CalculateMagicBaseDamage(
			skill_power,
			_read_attribute(attacker_stats, "MagPower", 0.0),
			_read_attribute(defender_stats, "MagResist", 0.0),
			_read_attribute(attacker_stats, "MagicPenetrationRate", 0.0),
			_read_attribute(attacker_stats, "FixedMagicPenetration", 0.0)
		)

	# 真实伤害不走攻防比值，仍然保留后续状态和属性克制修正入口。
	return skill_power


## 应用五行属性克制倍率，并保持伤害不会为负。
##
## @param payload 本次伤害载荷。
## @param defender 防御方节点；非怪物节点按无属性处理。
## @param damage 进入克制修正前的伤害值。
## @return 返回修正后的伤害值。
func _apply_element_multiplier(payload: Variant, defender: Node, damage: float) -> float:
	var target_element: int = 0

	if defender != null:
		# 怪物数据已迁移到 GDScript，属性克制读取统一走跨语言字段协议。
		var base_data: Variant = defender.get("BaseData")
		if base_data != null:
			target_element = _read_int(base_data, "ElementalProperty")

	var element_multiplier: float = ELEMENTAL_SYSTEM_SCRIPT.CalculateMultiplier(
		_read_int(payload, "Element"),
		target_element
	)

	return maxf(0.0, damage * element_multiplier)


## 应用随机浮动倍率，并保持伤害不会为负。
##
## @param damage 进入随机浮动前的伤害值。
## @return 返回修正后的伤害值。
func _apply_random_variance(damage: float) -> float:
	return maxf(
		0.0,
		damage
		* DAMAGE_FORMULA_SCRIPT.CalculateRandomVariance(
			RandomVarianceMin,
			RandomVarianceMax,
			_rng.randf()
		)
	)


## 按实际扣血量给伤害来源回复生命。
##
## @param source 伤害来源节点。
## @param attacker_stats 攻击方属性组件；为空时吸血率按 0 处理。
## @param actual_damage 本次实际扣血量。
## @return 无返回值。
func _apply_lifesteal(source: Node, attacker_stats: Node, actual_damage: int) -> void:
	var heal_amount: int = DAMAGE_FORMULA_SCRIPT.CalculateLifestealAmount(
		actual_damage,
		_read_attribute(attacker_stats, "LifestealRate", 0.0)
	)

	if heal_amount <= 0:
		return

	# 吸血回复同样走方法协议，保证 GDScript 生命组件可以接收治疗。
	var heal_component: Node = _find_component(source, HEALTH_COMPONENT_NAME)
	if heal_component != null:
		heal_component.call("Add", heal_amount)


## 读取跨语言数值组件的当前值。
##
## @param vital 生命或能量等数值组件节点。
## @return 当前值；节点缺失或字段类型不符时返回 0。
func _read_vital_current_value(vital: Node) -> int:
	if vital == null or not is_instance_valid(vital):
		return 0

	var value: Variant = vital.get("CurrentValue")
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)

	return 0


## 通过非 ref 包装方法协议应用一次状态伤害修正。
##
## @param status_component C# 垫片或 GDScript 生产状态组件节点；为空时原样返回。
## @param method_name 状态组件上等价旧 C# ref Hook 的非 ref 包装方法名。
## @param payload 本次伤害载荷。
## @param damage 进入修正前的伤害值。
## @return 修正后的伤害值；修正归零时由状态组件返回 0。
func _apply_status_damage_modifier(
	status_component: Node,
	method_name: String,
	payload: Variant,
	damage: float
) -> float:
	if status_component == null:
		return damage

	return float(status_component.call(method_name, payload, damage))


## 在实体自身或其 Components 子节点下查找组件。
##
## @param owner 实体根节点。
## @param component_name 组件节点名。
## @return 找到的组件节点；缺失时返回 null。
func _find_component(owner: Node, component_name: String) -> Node:
	if owner == null:
		return null

	var direct: Node = owner.get_node_or_null(component_name)
	if direct != null:
		return direct

	return owner.get_node_or_null("Components/%s" % component_name)


## 读取属性组件上的有效属性值。
##
## @param component 属性组件节点；为空时直接返回默认值。
## @param property_name 属性名，与旧 C# 导出属性逐字同名。
## @param default_value 组件缺失或字段类型不符时的默认值。
## @return 属性数值。
func _read_attribute(component: Node, property_name: String, default_value: float) -> float:
	if component == null:
		return default_value

	var value: Variant = component.get(property_name)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)

	return default_value


## 按属性名读取载荷中的节点字段。
##
## @param payload 伤害载荷。
## @param property_name 字段名。
## @return 节点对象；缺失时返回 null。
func _read_node(payload: Variant, property_name: String) -> Node:
	var value: Variant = payload.get(property_name)
	if value is Node:
		return value

	return null


## 按属性名读取载荷中的浮点字段。
##
## @param payload 伤害载荷。
## @param property_name 字段名。
## @return 浮点值；缺失时返回 0.0。
func _read_float(payload: Variant, property_name: String) -> float:
	var value: Variant = payload.get(property_name)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)

	return 0.0


## 按属性名读取载荷或资源对象中的整数字段。
##
## @param payload 伤害载荷或资源对象。
## @param property_name 字段名。
## @return 整数值；缺失时返回 0。
func _read_int(payload: Variant, property_name: String) -> int:
	var value: Variant = payload.get(property_name)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)

	return 0


## 判断载荷是否启用指定伤害修饰，等价旧 C# DamageModifierFlags 位判断。
##
## @param payload 伤害载荷。
## @param modifier 需要判断的修饰位。
## @return 启用该修饰时返回 true。
func _has_damage_modifier(payload: Variant, modifier: int) -> bool:
	var modifiers: int = _read_int(payload, "DamageModifiers")
	return modifier != 0 and (modifiers & modifier) == modifier


## 构造旧 C# 伤害结算结果，保持表现层读取协议不变。
##
## @param payload 本次伤害载荷；为空时表示载荷缺失的兜底结算。
## @param pre_guard_damage 护盾和伤害上限处理前的伤害候选值。
## @param actual_damage 目标生命实际减少的数值。
## @param is_evaded 本次伤害是否被闪避。
## @param is_critical 本次伤害是否暴击。
## @param is_lethal 本次伤害是否使目标生命归零。
## @return 结算结果对象；结果脚本缺失时返回 null。
func _new_result(
	payload: Variant,
	pre_guard_damage: int,
	actual_damage: int,
	is_evaded: bool,
	is_critical: bool,
	is_lethal: bool
) -> Variant:
	var result_script: Script = load(RESULT_SCRIPT_PATH)
	if result_script == null:
		push_error("DamageResolutionResult script is missing: %s" % RESULT_SCRIPT_PATH)
		return null

	return result_script.new(
		payload,
		pre_guard_damage,
		actual_damage,
		is_evaded,
		is_critical,
		is_lethal
	)


## 解析日志中的目标名称，保持旧 C# 的回退顺序。
##
## @param defender_root 防御方根节点。
## @param defender_components 防御方组件容器节点。
## @return 根节点名称；根节点缺失时回退到组件容器名称。
func _entity_name(defender_root: Node, defender_components: Node) -> String:
	if defender_root != null:
		return String(defender_root.name)

	return String(defender_components.name)


## 解析日志中的来源名称。
##
## @param source 伤害来源节点。
## @return 来源名称；缺失时返回旧 C# 的 Unknown 占位。
func _source_name(source: Node) -> String:
	if source != null:
		return String(source.name)

	return "Unknown"


## 读取载荷五行属性的枚举名称，保持旧 C# 日志文本。
##
## @param payload 伤害载荷。
## @return 枚举名称；越界时回退为整数文本。
func _element_name(payload: Variant) -> String:
	var element: int = _read_int(payload, "Element")
	if element < 0 or element >= ELEMENT_NAMES.size():
		return str(element)

	return ELEMENT_NAMES[element]


## 读取载荷伤害类型的枚举名称，保持旧 C# 日志文本。
##
## @param payload 伤害载荷。
## @return 枚举名称；越界时回退为整数文本。
func _damage_type_name(payload: Variant) -> String:
	var damage_type: int = _read_int(payload, "Type")
	if damage_type < 0 or damage_type >= DAMAGE_TYPE_NAMES.size():
		return str(damage_type)

	return DAMAGE_TYPE_NAMES[damage_type]


## 把布尔值格式化为旧 C# 的 True/False 文本。
##
## @param value 需要格式化的布尔值。
## @return 与 C# 布尔插值一致的字符串。
func _bool_text(value: bool) -> String:
	return "True" if value else "False"
