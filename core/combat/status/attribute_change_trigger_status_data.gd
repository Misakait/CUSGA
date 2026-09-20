extends "res://core/combat/status/status_effect_data.gd"

## 属性变化后触发效果的状态数据的生产 GDScript 实现
## （旧 C# AttributeChangeTriggerStatusData 的等价实现）。
##
## 触发判定与效果执行由 GDScript AttributeChangeTriggerStatusInstance 完成；本资源只
## 声明目标属性、变化方向与触发效果列表。旧 C# 实例保留为兼容垫片。

## 运行时状态实例脚本路径；实例已是 GDScript 生产实现，旧 C# 实例保留为兼容垫片。
const INSTANCE_SCRIPT_PATH: String = \
	"res://core/combat/status/attribute_change_trigger_status_instance.gd"

## 触发监听的目标属性枚举整数，沿用旧 C# 默认值 AttributeType 的第一个取值。
@export var TargetAttribute: int = 0

## 触发监听的变化方向枚举整数，沿用旧 C# 默认值 AttributeChangeDirection.Any。
@export var Direction: int = 0

## 触发时执行的效果列表；效果与技能效果同属 CardEffect 家族，可为 GDScript 或旧 C# 垫片。
@export var Effects: Array[Resource] = []


## 创建运行时触发状态实例。
##
## @param source 施加状态的来源节点。
## @param owner 拥有状态的目标节点。
## @return 对应的 GDScript 属性变化触发状态实例。
func CreateInstance(source: Node, owner: Node) -> RefCounted:
	return load(INSTANCE_SCRIPT_PATH).new(self, source, owner)
