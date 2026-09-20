extends "res://core/combat/status/status_effect_data.gd"

## Boss 单次扣血上限状态数据的生产 GDScript 实现（旧 C# BossDamageCapStatusData 的等价实现）。
##
## 上限钳制与伤害上限记录由 GDScript BossDamageCapStatusInstance 完成；本资源只提供
## “单次扣血不得超过最大生命的比例”。旧 C# 实例保留为兼容垫片。

## 运行时状态实例脚本路径；实例已是 GDScript 生产实现，旧 C# 实例保留为兼容垫片。
const INSTANCE_SCRIPT_PATH: String = \
	"res://core/combat/buffs/boss_damage_cap_status_instance.gd"

## 单次扣血不得超过最大生命的该比例，沿用旧 C# 默认值 0.10。
## 编辑器范围与旧 C# 的 PropertyHint.Range("0,1,0.01") 一致。
@export_range(0.0, 1.0, 0.01) var MaxHealthDamageRatio: float = 0.10


## 创建运行时扣血上限状态实例。
##
## @param source 施加状态的来源节点。
## @param owner 拥有状态的目标节点。
## @return 对应的 GDScript 扣血上限状态实例。
func CreateInstance(source: Node, owner: Node) -> RefCounted:
	return load(INSTANCE_SCRIPT_PATH).new(self, source, owner)
