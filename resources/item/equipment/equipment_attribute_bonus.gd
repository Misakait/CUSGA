extends Resource
class_name EquipmentAttributeBonus

## 装备单项属性的随机范围配置；仅保存配置，不持有某件装备的随机结果。

## 属性编号沿用战斗属性的 0～14；例如 MaxHealth 是生命上限，不是立即治疗。
@export_enum("PhysAtk:0", "PhysDef:1", "MagPower:2", "MagResist:3", "Speed:4", "MaxHealth:5", "MaxEnergy:6", "FixedPhysPenetration:7", "PhysPenetrationRate:8", "FixedMagicPenetration:9", "MagicPenetrationRate:10", "CritRate:11", "CritDamage:12", "EvasionRate:13", "LifestealRate:14") var Attribute: int = 0

## 属性加成下界；与上界相同表示固定值，允许负数。
@export var MinValue: int = 0

## 属性加成上界；运行时安全整理倒置的上下界。
@export var MaxValue: int = 0
