extends "res://resources/item/base_card_data.gd"

## 战斗技能资源的生产 GDScript 实现。
##
## 旧 C# CombatSkillData 继承 BaseCardData；GDScript 无法继承 C# 脚本，因此这里继承
## 字段名逐字一致的 GDScript BaseCardData，并重新声明技能自身的 Element / TargetingType
## / Effects 字段。执行顺序（开启技能作用域 → 逐个效果执行 → 统一收尾状态）保持不变。
## 脚本不声明 class_name，避免与仍在使用的 C# CombatSkillData 全局类型重名。
## 伤害效果识别走导出字段协议（DAMAGE_EFFECT_REQUIRED_FIELDS），不依赖语言身份。

## 技能执行修正上下文的脚本路径；生产实现已迁移为 GDScript，C# 垫片只作回滚输入。
const MODIFIER_CONTEXT_SCRIPT_PATH: String = \
	"res://core/combat/skills/skill_execution_modifier_context.gd"

## 伤害效果必备字段协议。
##
## 为什么不用 `effect is DamageEffect`：那是语言身份判定，C# 垫片退役后该标识符无法解析，
## 整个技能脚本会直接加载失败；按导出字段判定能让两种语言的实现共用同一条判据。
const DAMAGE_EFFECT_REQUIRED_FIELDS: Array[StringName] = [
	&"BaseDamage",
	&"HitCount",
	&"PrimaryDamageMultiplier",
]

## 旧 C# skill_status_component 挂载路径，与 CardEffect 基类保持同一顺序。
const STATUS_COMPONENT_PATHS: Array[String] = [
	"StatusComponent",
	"Components/StatusComponent",
]

## 与 C# SkillTargetingType 对齐的目标类型取值。
const TARGETING_SELF: int = 0
const TARGETING_SINGLE_ENEMY: int = 1
const TARGETING_ALL_ENEMIES: int = 2
const TARGETING_ANY_SINGLE_UNIT: int = 3
const TARGETING_ALL_UNITS: int = 4
const TARGETING_RANDOM_ENEMY: int = 5
const TARGETING_SPREAD_FROM_ENEMY: int = 6

## 技能五行属性，沿用旧 C# 默认值 None。
@export var Element: int = 0

## 技能目标类型，沿用旧 C# 默认值 SingleEnemy。
@export var TargetingType: int = TARGETING_SINGLE_ENEMY

## 技能效果列表；使用通用 Resource 数组，可同时承载旧 C# CardEffect 与 GDScript 效果。
@export var Effects: Array[Resource] = []


## 判断技能是否需要显式选择目标，规则与旧 C# RequiresTarget 完全一致。
##
## @return 需要玩家或调用方指定目标时返回 true。
func RequiresTarget() -> bool:
	return TargetingType != TARGETING_SELF \
		and TargetingType != TARGETING_ALL_ENEMIES \
		and TargetingType != TARGETING_ALL_UNITS \
		and TargetingType != TARGETING_RANDOM_ENEMY


## 执行技能：先开启技能执行作用域，再顺序执行所有效果，最后统一收尾状态。
##
## @param context 技能执行上下文，允许旧 C# SkillExecutionContext。
## @return 无。
func Execute(context: RefCounted) -> void:
	if context == null:
		push_error("CombatSkillData '%s' executed with null context." % CardId)
		return

	var targets: Variant = context.get("Targets")
	if not (targets is Array) or (targets as Array).is_empty():
		push_error("CombatSkillData '%s' executed with empty targets." % CardId)
		return

	var source: Node = context.get("Source")
	var status_component := _find_status_component(source)
	var modifier_context: RefCounted = null

	if status_component != null:
		# 只有确实需要状态 Hook 时才构造修正上下文：惰性构造可以让没有状态组件时的
		# 执行路径与上下文实现解耦。
		modifier_context = load(MODIFIER_CONTEXT_SCRIPT_PATH).new(
			source,
			self,
			context,
			_has_damage_effect()
		)
		status_component.call("ProcessBeforeSkillExecution", modifier_context)

	for effect: Resource in _read_effects():
		if effect == null:
			continue
		# 旧 C# 效果走 CardEffect.Execute 覆盖；GDScript 效果由同一协议方法承接。
		effect.call("Execute", context)

	if status_component != null:
		status_component.call("ProcessAfterSkillExecution", modifier_context)


## 判断技能是否包含至少一个伤害效果。
##
## @return 包含伤害效果时返回 true。
func _has_damage_effect() -> bool:
	for effect: Resource in _read_effects():
		if _is_damage_effect(effect):
			return true
	return false


## 按导出字段协议判断一个效果资源是否属于伤害效果。
##
## 判据是「同时具备 BaseDamage / HitCount / PrimaryDamageMultiplier」三个字段，
## 因此旧 C# 垫片与 GDScript 生产实现会被同一条规则接受，普通效果与空值都被拒绝。
##
## @param effect 待判定的效果对象，允许任意语言实现或空值。
## @return 属于伤害效果时返回 true。
func _is_damage_effect(effect: Variant) -> bool:
	if not (effect is Resource):
		return false
	var resource: Resource = effect
	for field_name: StringName in DAMAGE_EFFECT_REQUIRED_FIELDS:
		if resource.get(field_name) == null:
			return false
	return true


## 读取效果列表，过滤非 Resource 值并保留配置顺序。
##
## @return 只包含 Resource 的效果数组。
func _read_effects() -> Array[Resource]:
	var effects: Array[Resource] = []
	for value: Variant in Effects:
		if value is Resource:
			effects.append(value)
	return effects


## 查找施放者身上的状态组件，路径顺序与旧 C# ComponentLookup 一致。
##
## @param owner 施放者节点，可为空。
## @return 具备技能作用域协议的组件节点；缺失时返回 null。
func _find_status_component(owner: Node) -> Object:
	if owner == null or not is_instance_valid(owner):
		return null
	for path: String in STATUS_COMPONENT_PATHS:
		var node: Node = owner.get_node_or_null(path)
		if node != null and node.has_method("ProcessBeforeSkillExecution"):
			return node
	var unique_node: Node = owner.get_node_or_null("%StatusComponent")
	if unique_node != null:
		return unique_node
	return null
