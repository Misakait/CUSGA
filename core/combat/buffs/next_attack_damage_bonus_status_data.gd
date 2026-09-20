extends "res://core/combat/status/status_effect_data.gd"

## 接下来若干张攻击牌每段基础伤害修正状态数据的生产 GDScript 实现
## （旧 C# NextAttackDamageBonusStatusData 的等价实现）。
##
## 每段伤害修正与限次消耗由 GDScript NextAttackDamageBonusStatusInstance 完成；本资源只声明
## “每层每段固定伤害加成”与“可影响的攻击技能次数”。旧 C# 实例保留为兼容垫片。

## 运行时状态实例脚本路径；实例已是 GDScript 生产实现，旧 C# 实例保留为兼容垫片。
const INSTANCE_SCRIPT_PATH: String = \
	"res://core/combat/buffs/next_attack_damage_bonus_status_instance.gd"

## 每层为每段基础伤害提供的固定加成，沿用旧 C# 默认值 0。
@export var FlatSegmentDamageBonusPerStack: int = 0

## 可影响的攻击技能次数；0 表示持续期间不限次数，沿用旧 C# 默认值 1。
@export var AttackSkillUses: int = 1


## 创建运行时每段基础伤害修正状态实例。
##
## @param source 施加状态的来源节点。
## @param owner 拥有状态的目标节点。
## @return 对应的 GDScript 每段基础伤害修正状态实例。
func CreateInstance(source: Node, owner: Node) -> RefCounted:
	return load(INSTANCE_SCRIPT_PATH).new(self, source, owner)
