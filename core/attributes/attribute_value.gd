extends RefCounted

## 单条属性值，等价迁移自 core/attributes/Attributes.cs 的 Attribute 类。
##
## 属性组件已迁移到 GDScript，本脚本只作为纯数据载体：字段名与旧 C# 逐字一致，
## 不声明 class_name，避免与仍在使用的 C# 同名类型重名。

## 属性类型整数值，等价旧 C# AttributeType。
var Type: int = 0
## 展示名，例如“物理攻击”。
var DisplayName: String = ""
## 基础值。
var BaseValue: float = 0.0
## 来自天赋、装备、永久药水等提供的额外固定加成。
var BonusValue: float = 0.0
## 玩家投入的属性点数。
var AllocatedPoints: int = 0
## 每投入 1 点属性的成长值。
var GrowthPerPoint: float = 0.0
## 动态计算的最终原始值：基础值 + 固定加成 + 投入点数 * 成长值。
var RawValue: float:
	get:
		return BaseValue + BonusValue + AllocatedPoints * GrowthPerPoint


## 初始化一条属性值。
##
## @param type 属性类型整数值。
## @param display_name 展示名。
## @param base_value 基础值。
## @param growth_per_point 每点成长值。
## @return 无返回值。
func Initialize(
	type: int, display_name: String, base_value: float, growth_per_point: float
) -> void:
	Type = type
	DisplayName = display_name
	BaseValue = base_value
	BonusValue = 0.0
	AllocatedPoints = 0
	GrowthPerPoint = growth_per_point


## 增加投入点数。
##
## @param amount 增加的点数。
## @return 无返回值。
func AddPoint(amount: int) -> void:
	AllocatedPoints += amount


## 增加固定加成。
##
## @param amount 增加的固定值。
## @return 无返回值。
func AddBonus(amount: float) -> void:
	BonusValue += amount


## 减少固定加成。
##
## @param amount 减少的固定值。
## @return 无返回值。
func RemoveBonus(amount: float) -> void:
	BonusValue -= amount


## 直接设置基础值，等价旧 C# internal SetBaseValue。
##
## @param value 新的基础值。
## @return 无返回值。
func SetBaseValue(value: float) -> void:
	BaseValue = value
