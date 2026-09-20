extends "res://core/combat/status/status_effect_data.gd"

## 脆弱状态数据的生产 GDScript 实现（旧 C# VulnerableStatusData 的等价实现）。
##
## 受击增伤由 GDScript VulnerableStatusInstance 完成；本资源只提供目标伤害类型与增伤倍率。
## 旧 C# 实例保留为兼容垫片。

## 运行时状态实例脚本路径；实例已是 GDScript 生产实现，旧 C# 实例保留为兼容垫片。
const INSTANCE_SCRIPT_PATH: String = "res://core/combat/buffs/vulnerable_status_instance.gd"

## 触发增伤的伤害类型枚举整数，沿用旧 C# 默认值 DamageType.Physical = 0。
@export var TargetDamageType: int = 0

## 受击增伤倍率，沿用旧 C# 默认值 1.5。
@export var DamageMultiplier: float = 1.5


## 创建运行时脆弱状态实例。
##
## @param source 施加状态的来源节点。
## @param owner 拥有状态的目标节点。
## @return 对应的 GDScript 脆弱状态实例。
func CreateInstance(source: Node, owner: Node) -> RefCounted:
	return load(INSTANCE_SCRIPT_PATH).new(self, source, owner)
