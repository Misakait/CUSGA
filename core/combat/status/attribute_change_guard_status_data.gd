extends "res://core/combat/status/status_effect_data.gd"

## 属性变化拦截状态数据的生产 GDScript 实现（旧 C# AttributeChangeGuardStatusData 的等价实现）。
##
## 拦截判定与变化量改写由 GDScript AttributeChangeGuardStatusInstance 完成；本资源只声明
## 目标属性、变化方向、取消开关、变化量倍率与取值上下限。旧 C# 实例保留为兼容垫片。

## 运行时状态实例脚本路径；实例已是 GDScript 生产实现，旧 C# 实例保留为兼容垫片。
const INSTANCE_SCRIPT_PATH: String = \
	"res://core/combat/status/attribute_change_guard_status_instance.gd"

## 拦截监听的目标属性枚举整数，沿用旧 C# 默认值 AttributeType 的第一个取值（PhysAtk = 0）。
@export var TargetAttribute: int = 0

## 拦截监听的变化方向枚举整数，沿用旧 C# 默认值 AttributeChangeDirection.Any = 0。
@export var Direction: int = 0

## true = 直接取消这次属性变化，沿用旧 C# 默认值 false。
@export var CancelChange: bool = false

## 变化量倍率，例如 0.5 = 变化量减半、2.0 = 变化量翻倍，沿用旧 C# 默认值 1。
@export var DeltaMultiplier: float = 1.0

## 是否启用“变化后取值”下限钳制，沿用旧 C# 默认值 false。
@export var EnableMinValue: bool = false

## 启用下限钳制时使用的最小值，沿用旧 C# 默认值 0。
@export var MinValue: float = 0.0

## 是否启用“变化后取值”上限钳制，沿用旧 C# 默认值 false。
@export var EnableMaxValue: bool = false

## 启用上限钳制时使用的最大值，沿用旧 C# 默认值 0。
@export var MaxValue: float = 0.0


## 创建运行时属性变化拦截状态实例。
##
## @param source 施加状态的来源节点。
## @param owner 拥有状态的目标节点。
## @return 对应的 GDScript 属性变化拦截状态实例。
func CreateInstance(source: Node, owner: Node) -> RefCounted:
	return load(INSTANCE_SCRIPT_PATH).new(self, source, owner)
