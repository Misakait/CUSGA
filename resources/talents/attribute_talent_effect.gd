extends "res://resources/talents/talent_effect.gd"

## 为玩家指定属性增加永久数值的天赋效果。

## AttributeType 的固定显示名称，顺序与 C# 枚举 0..14 保持一致。
const ATTRIBUTE_NAMES: Array[String] = [
	"PhysAtk",
	"PhysDef",
	"MagPower",
	"MagResist",
	"Speed",
	"MaxHealth",
	"MaxEnergy",
	"FixedPhysPenetration",
	"PhysPenetrationRate",
	"FixedMagicPenetration",
	"MagicPenetrationRate",
	"CritRate",
	"CritDamage",
	"EvasionRate",
	"LifestealRate",
]

## 需要增加的 AttributeType 固定整数值。
@export_enum(
	"PhysAtk:0",
	"PhysDef:1",
	"MagPower:2",
	"MagResist:3",
	"Speed:4",
	"MaxHealth:5",
	"MaxEnergy:6",
	"FixedPhysPenetration:7",
	"PhysPenetrationRate:8",
	"FixedMagicPenetration:9",
	"MagicPenetrationRate:10",
	"CritRate:11",
	"CritDamage:12",
	"EvasionRate:13",
	"LifestealRate:14",
) var TargetAttribute: int = 0

## 永久增加的固定数值。
@export var BonusValue: float = 0.0


## 对玩家直属的 AttributeComponent 应用永久加成。
##
## 参数 target_player：接收效果的玩家节点。
## 返回值：无。
func Apply(target_player: Node) -> void:
	var attribute_component := target_player.get_node_or_null("AttributeComponent")
	if attribute_component == null:
		return

	attribute_component.call("AddPermanentBonus", TargetAttribute, BonusValue)
	var attribute_name := str(TargetAttribute)
	if TargetAttribute >= 0 and TargetAttribute < ATTRIBUTE_NAMES.size():
		attribute_name = ATTRIBUTE_NAMES[TargetAttribute]
	print("天赋生效：%s 永久增加了 %s！" % [attribute_name, BonusValue])
