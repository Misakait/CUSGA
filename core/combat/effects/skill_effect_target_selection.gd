extends RefCounted

## 技能效果目标选择条目的生产 GDScript 实现，等价迁移自 C# SkillEffectTargetSelection。
##
## 旧 C# 是只读结构体，字段 Unit / Role / IsSource 与派生布尔 IsPrimary / IsSecondary
## 都是只读语义：GDScript 侧把派生字段改成 getter，保证外部无法写出与 Role 矛盾的状态。
## 字段名与旧 C# 逐字一致，C#（`SkillEffectTargetScopeUtility`）与 GDScript 都按字段协议读取。
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。

## 本脚本路径：静态工厂在没有 class_name 的前提下必须靠它构造实例。
const SELF_PATH: String = "res://core/combat/effects/skill_effect_target_selection.gd"

## 目标角色枚举整数，取值与旧 C# SkillTargetRole 一致。
const ROLE_PRIMARY: int = 0
const ROLE_SECONDARY: int = 1

## 被选中的节点。
var Unit: Node = null
## 目标角色枚举整数，等价旧 C# Role。
var Role: int = ROLE_PRIMARY
## 该条目是否代表施放者自身，等价旧 C# IsSource。
var IsSource: bool = false


## 构造目标选择条目。
##
## @param unit 被选中的节点。
## @param role 目标角色枚举整数。
## @param is_source 该条目是否代表施放者自身。
## @return 无返回值。
func _init(unit: Node, role: int, is_source: bool) -> void:
	Unit = unit
	Role = role
	IsSource = is_source


## 是否为「非自身」的主目标，等价旧 C# IsPrimary。
##
## @return 既不是来源、角色又是主目标时返回 true。
var IsPrimary: bool:
	get:
		return not IsSource and Role == ROLE_PRIMARY


## 是否为「非自身」的次目标，等价旧 C# IsSecondary。
##
## @return 既不是来源、角色又是次目标时返回 true。
var IsSecondary: bool:
	get:
		return not IsSource and Role == ROLE_SECONDARY


## 以施放者自身构造选择条目，等价旧 C# FromSource。
##
## 旧 C# 固定把自身记为 Primary 且 IsSource=true，因此 IsPrimary / IsSecondary 都为 false。
##
## @param source 施放者节点。
## @return 代表施放者自身的选择条目。
static func FromSource(source: Node) -> RefCounted:
	return load(SELF_PATH).new(source, ROLE_PRIMARY, true)


## 以技能目标条目构造选择条目，等价旧 C# FromTarget。
##
## @param target 技能目标条目（旧 C# SkillTarget 或 GDScript skill_target.gd）。
## @return 代表该目标的选择条目；目标为空时返回 null。
static func FromTarget(target: Variant) -> RefCounted:
	if target == null:
		return null

	var target_object: Object = target as Object
	if target_object == null:
		return null

	return load(SELF_PATH).new(
		target_object.get("Unit") as Node,
		int(target_object.get("Role")),
		false
	)
