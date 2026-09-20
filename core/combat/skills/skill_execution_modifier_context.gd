extends RefCounted

## 整张技能执行期间的修正上下文，等价迁移自
## core/combat/skills/SkillExecutionModifierContext.cs。
##
## 状态 Hook 用它在技能执行前后读取施放者/技能数据，并标记「本次攻击技能完成后需要扣减使用次数」
## 的限次状态。字段名、方法名与旧 C# 逐字一致，状态实例（C# 或 GDScript）都按方法协议读写。
## 内部集合在旧 C# 里是 HashSet<StringName>，GDScript 侧用「去重数组 + 插入顺序」保持同样的
## 「每个 Id 只出现一次」语义。脚本不声明 class_name，避免与 C# 全局类型重名。

## 本次技能的施放者。
var Source: Node = null
## 本次执行的技能数据资源。
var Skill: Resource = null
## 本次技能执行上下文。
var SkillContext: Variant = null
## 本次技能是否包含至少一个伤害效果。
var HasDamageEffect: bool = false

## 需要扣减使用次数的状态 Id 集合，按首次标记顺序保存。
var _status_ids_marked_for_consumption: Array[StringName] = []


## 构造技能执行修正上下文。
##
## @param source 本次技能的施放者。
## @param skill 本次执行的技能数据。
## @param skill_context 本次技能执行上下文。
## @param has_damage_effect 本次技能是否包含至少一个伤害效果。
## @return 无返回值。
func _init(
	source: Node, skill: Resource, skill_context: Variant, has_damage_effect: bool
) -> void:
	Source = source
	Skill = skill
	SkillContext = skill_context
	HasDamageEffect = has_damage_effect


## 是否应视为攻击技能，等价旧 C# IsAttackSkill。
var IsAttackSkill: bool:
	get:
		return HasDamageEffect


## 待消费状态 Id 集合的只读视图（与内部集合同序）。
var StatusIdsMarkedForConsumption: Array[StringName]:
	get:
		return _status_ids_marked_for_consumption


## 标记指定状态在整张攻击技能完成后扣减一次使用次数。
##
## @param status_id 需要扣减使用次数的状态唯一标识；为空时忽略。
## @return 无返回值。
func MarkStatusForConsumption(status_id: StringName) -> void:
	if status_id == &"":
		return

	# 等价旧 C# HashSet.Add：同一个 Id 重复标记只保留一次。
	if _status_ids_marked_for_consumption.has(status_id):
		return

	_status_ids_marked_for_consumption.append(status_id)


## 为 GDScript 状态组件读取待消费状态 Id 提供可跨语言传递的副本。
##
## @return 待扣减使用次数的状态 Id 数组副本，顺序与内部集合枚举顺序一致。
func GetStatusIdsMarkedForConsumptionSnapshot() -> Array[StringName]:
	return _status_ids_marked_for_consumption.duplicate()
