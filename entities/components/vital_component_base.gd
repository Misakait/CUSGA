extends Node

## 数值型资源组件的 GDScript 生产实现，等价迁移自 VitalComponentBase.cs。
##
## 只维护「当前值 / 上限」与恢复、扣除结算，并通过稳定信号通知视图；
## 生命、能量、饱食等具体语义由子类负责，本文件不复制任何玩法规则。
##
## 跨语言边界是稳定协议：ValueChanged(currentValue, maxValue)、Depleted()、
## CurrentValue、MaxValue、InitializeMax、SetMaxValuePreservingCurrent、Add 与 Subtract，
## C# 与 GDScript 消费者按同一套名字读写；CurrentValue 不是序列化字段，与原实现一致。

## 上限或当前值发生变化时发出。
signal ValueChanged(current_value: int, max_value: int)

## 当前值归零时发出。
signal Depleted()

## 资源上限；场景可以覆盖序列化值。
@export var MaxValue: int = 100

## 当前资源值；进入场景树时补满到上限。
var CurrentValue: int = 0


## 进入场景树时把当前值补满到上限。
##
## @return 无。
func _ready() -> void:
	CurrentValue = MaxValue


## 初始化资源上限，并将当前值补满到新的上限。
##
## @param new_max_value 新的资源上限。
## @return 无。
func InitializeMax(new_max_value: int) -> void:
	MaxValue = new_max_value
	CurrentValue = MaxValue
	ValueChanged.emit(CurrentValue, MaxValue)


## 更新资源上限并保留当前值，只在当前值超出新上限时进行钳制。
##
## @param new_max_value 新的资源上限；低于 1 时按 1 处理。
## @return 无。
func SetMaxValuePreservingCurrent(new_max_value: int) -> void:
	var normalized_max_value: int = maxi(1, new_max_value)
	var old_max_value: int = MaxValue
	var old_current_value: int = CurrentValue

	MaxValue = normalized_max_value
	CurrentValue = clampi(CurrentValue, 0, MaxValue)

	# 只有真的变化才通知视图，避免属性重算刷屏。
	if old_max_value != MaxValue or old_current_value != CurrentValue:
		ValueChanged.emit(CurrentValue, MaxValue)


## 增加资源值并返回实际恢复量。
##
## @param amount 尝试增加的资源值。
## @return 受上限限制后的实际增加量。
func Add(amount: int) -> int:
	if amount <= 0 or CurrentValue >= MaxValue:
		return 0

	var old_value: int = CurrentValue
	CurrentValue = mini(CurrentValue + amount, MaxValue)
	ValueChanged.emit(CurrentValue, MaxValue)

	return CurrentValue - old_value


## 扣除资源值并返回实际扣除量。
##
## @param amount 尝试扣除的资源值。
## @return 受当前值限制后的实际扣除量。
func Subtract(amount: int) -> int:
	if amount <= 0 or CurrentValue <= 0:
		return 0

	var old_value: int = CurrentValue
	CurrentValue = maxi(CurrentValue - amount, 0)
	ValueChanged.emit(CurrentValue, MaxValue)

	# 归零必须在 ValueChanged 之后发出，保持旧实现的信号顺序。
	if CurrentValue <= 0:
		Depleted.emit()

	return old_value - CurrentValue
