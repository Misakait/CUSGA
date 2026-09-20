extends RefCounted

## 属性修饰条目的 GDScript 等价实现，等价迁移自 core/attributes/AttributeModifier.cs。
##
## 旧 C# 是 readonly record struct；GDScript 没有结构体，所以这里用 RefCounted +
## 构造参数表达同一份字段面：Type / Mode / ValuePerStack / Stacks / SourceId。
## 该条目本身不落盘，跨语言边界统一走 AttributeModifierDataProtocol 的字典出口
## （Type / Mode / ValuePerStack / Stacks / SourceId），因此字段名必须逐字一致。
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。

## 属性修饰模式；0..2 分别对应原 C# AttributeModifierMode。
enum AttributeModifierMode {
	## 直接叠加固定值。
	FlatAdd = 0,
	## 按百分比叠加到总量。
	PercentAdd = 1,
	## 按百分比乘算。
	PercentMul = 2,
}

## 受该条目影响的属性类型（AttributeType 枚举整数）。
var Type: int = 0
## 修正模式（AttributeModifierMode 枚举整数）。
var Mode: int = 0
## 每一层提供的修正值。
var ValuePerStack: float = 0.0
## 当前层数。
var Stacks: int = 0
## 修正来源标识，用于同源覆盖与诊断。
var SourceId: StringName = &""


## 构造一条属性修饰条目。
##
## @param type 受影响的属性类型整数。
## @param mode 修正模式整数。
## @param value_per_stack 每层修正值。
## @param stacks 层数。
## @param source_id 修正来源标识。
## @return 无返回值。
func _init(
	type: int, mode: int, value_per_stack: float, stacks: int, source_id: StringName
) -> void:
	Type = type
	Mode = mode
	ValuePerStack = value_per_stack
	Stacks = stacks
	SourceId = source_id


## 该条目的总修正量。
##
## 旧 C# 调用点统一按 ValuePerStack * Stacks 计算总量，这里提供同一个入口，
## 避免 GDScript 调用方各处重算而出现取整差异。
##
## @return 每层修正值乘以层数。
func TotalValue() -> float:
	return ValuePerStack * float(Stacks)


## 转成跨语言字典。
##
## 字段名与取值类型必须与 AttributeModifierDataProtocol.ToDictionary 逐字一致，
## 属性组件（GDScript）只按该字典形状读取。
##
## @return 字段为 Type / Mode / ValuePerStack / Stacks / SourceId 的字典。
func ToDictionary() -> Dictionary:
	return {
		"Type": Type,
		"Mode": Mode,
		"ValuePerStack": ValuePerStack,
		"Stacks": Stacks,
		"SourceId": SourceId,
	}
