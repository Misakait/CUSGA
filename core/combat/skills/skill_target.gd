extends RefCounted

## 技能目标条目的 GDScript 生产实现，等价迁移自 core/combat/skills/SkillTarget.cs。
##
## 字段名与旧 C# 逐字一致（Unit / Role / RoleId / IsPrimary / IsSecondary）：技能效果脚本
## 与控制流都按字段协议读取目标，两种语言的目标对象因此可以互换。
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。

## 目标角色枚举，取值与旧 C# SkillTargetRole 一致。
const ROLE_PRIMARY: int = 0
const ROLE_SECONDARY: int = 1

## 目标节点。
var Unit: Node = null
## 目标角色枚举整数。
var Role: int = ROLE_PRIMARY


## 构造技能目标条目。
##
## @param unit 目标节点。
## @param role 目标角色枚举整数。
## @return 无返回值。
func _init(unit: Node, role: int) -> void:
	Unit = unit
	Role = role


## 目标角色枚举整数，等价旧 C# RoleId。
var RoleId: int:
	get:
		return Role


## 是否为主目标，等价旧 C# IsPrimary。
var IsPrimary: bool:
	get:
		return Role == ROLE_PRIMARY


## 是否为次目标，等价旧 C# IsSecondary。
var IsSecondary: bool:
	get:
		return Role == ROLE_SECONDARY
