extends "res://core/combat/status/status_effect_data.gd"

## 属性修正状态数据的生产 GDScript 实现（旧 C# AttributeModifierStatusData 的等价实现）。
##
## 该资源只保存“每一层提供哪些属性修正条目”；属性的实际重算由 GDScript 状态实例提供，
## 旧 C# 实例与 C# AttributeComponent 保留为兼容垫片。

## 运行时状态实例脚本路径；实例已是 GDScript 生产实现，旧 C# 实例保留为兼容垫片。
const INSTANCE_SCRIPT_PATH: String = \
	"res://core/combat/buffs/attribute_modifier_status_instance.gd"

## 每一层提供的属性修正条目列表。
## 条目可以为 GDScript attribute_modifier_data.gd，也可以是旧 C# AttributeModifierData 垫片。
@export var Modifiers: Array[Resource] = []


## 创建运行时状态实例。
##
## @param source 施加状态的来源节点。
## @param owner 拥有状态的目标节点。
## @return 对应的 GDScript 属性修正状态实例。
func CreateInstance(source: Node, owner: Node) -> RefCounted:
	return load(INSTANCE_SCRIPT_PATH).new(self, source, owner)
