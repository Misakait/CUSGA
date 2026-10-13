extends Resource
class_name EquipmentSetAttributeBonus

## 套装阶级的单项固定属性配置；保留原套装浮点数值，不进行随机。

## 属性编号沿用战斗属性的 0～14。
@export_enum("PhysAtk:0", "PhysDef:1", "MagPower:2", "MagResist:3", "Speed:4", "MaxHealth:5", "MaxEnergy:6", "FixedPhysPenetration:7", "PhysPenetrationRate:8", "FixedMagicPenetration:9", "MagicPenetrationRate:10", "CritRate:11", "CritDamage:12", "EvasionRate:13", "LifestealRate:14") var Attribute: int = 0

## 激活阶级后增加的属性原值；允许负数，百分率属性沿用小数单位。
@export var Value: float = 0.0
