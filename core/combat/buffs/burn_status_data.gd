extends "res://core/combat/status/status_effect_data.gd"

## 灼烧状态数据的生产 GDScript 实现（旧 C# BurnStatusData 的等价实现）。
##
## 每回合开始结算的持续伤害由 GDScript BurnStatusInstance 完成；本资源只提供伤害数值、
## 伤害类型/五行与修饰标志。旧 C# 实例保留为兼容垫片。

## 运行时状态实例脚本路径；实例已是 GDScript 生产实现，旧 C# 实例保留为兼容垫片。
const INSTANCE_SCRIPT_PATH: String = "res://core/combat/buffs/burn_status_instance.gd"

## 每层每回合造成的持续伤害，沿用旧 C# 默认值 5。
@export var DamagePerStack: float = 5.0

## 持续伤害类型枚举整数，沿用旧 C# 默认值 DamageType.Magic。
@export var DamageType: int = 1

## 持续伤害五行属性枚举整数，沿用旧 C# 默认值 ElementType.Fire。
@export var Element: int = 5

## 持续伤害启用的直接攻击修饰标志位，沿用旧 C# 默认值 0（不启用，避免被闪避/暴击/浮动/吸血）。
@export var DamageModifiers: int = 0


## 创建运行时灼烧状态实例。
##
## @param source 施加状态的来源节点。
## @param owner 拥有灼烧的目标节点。
## @return 对应的 GDScript 灼烧状态实例。
func CreateInstance(source: Node, owner: Node) -> RefCounted:
	return load(INSTANCE_SCRIPT_PATH).new(self, source, owner)
