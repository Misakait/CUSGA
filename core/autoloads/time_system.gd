extends Node

## 时间系统的 GDScript 生产实现。
##
## 公开属性、信号和方法名保持旧 C# TimeSystem 的协议，供 UI、地图和
## C# 与 GDScript 消费者统一通过 Autoload Node 的稳定动态协议访问。

## 每个昼夜阶段包含的时间点数。
const PhaseLength: int = 100

## 地图移动默认消耗的时间点数，与 TimeCosts.MapMove 保持一致。
@export var MapMoveTimeCost: int = 10

## 昼夜阶段切换信号。
signal DayNightToggled(is_night: bool)
## 天数增加信号。
signal DayPassed(current_day: int)
## 每七天触发一次天赋选择信号。
signal TalentSelectionTriggered
## 完整时间快照信号。
signal TimeChanged(total_time_passed: int, current_day: int, is_night: bool, phase_progress: int, phase_length: int)

## 开局以来累计的时间点数。
var _total_time_passed: int = 0
## 当前游戏天数，从第一天开始计数。
var _current_day: int = 1
## 当前是否处于夜晚阶段。
var IsNight: bool = false

## 读取累计时间。
func get_TotalTimePassed() -> int:
	return _total_time_passed

## 读取当前天数。
func get_CurrentDay() -> int:
	return _current_day

## 读取当前阶段进度。
func get_PhaseProgress() -> int:
	return _total_time_passed % PhaseLength

## 初始化后发送一次完整时间快照。
func _ready() -> void:
	_emit_time_changed()

## 增加时间并处理所有跨阶段事件。
## @param amount 本次增加的时间点数；非正数会被忽略。
func PassTime(amount: int) -> void:
	if amount <= 0:
		return
	var previous_time: int = _total_time_passed
	_total_time_passed += amount
	print("时间流逝了 %d 点，当前总时间：%d" % [amount, _total_time_passed])
	_check_time_transitions(previous_time, _total_time_passed)
	_emit_time_changed()

## 设置地图移动耗时。
## @param amount 新的正数耗时；非正数不会覆盖当前值。
func SetMapMoveTimeCost(amount: int) -> void:
	if amount > 0:
		MapMoveTimeCost = amount

## 使用当前地图移动耗时推进时间。
func PassMapMoveTime() -> void:
	PassTime(MapMoveTimeCost)


## 应用局内快照时间，保持昼夜状态与累计点数一致。
## @param total_time_passed 累计时间点数。
## @param current_day 当前天数。
## @param is_night 当前昼夜状态。
## @return 无返回值。
func RestoreSnapshot(total_time_passed: int, current_day: int, is_night: bool) -> void:
	_total_time_passed = maxi(total_time_passed, 0)
	_current_day = maxi(current_day, 1)
	IsNight = is_night
	_emit_time_changed()

## 对外提供 C# PascalCase 属性的动态读取协议。
func _get(property: StringName) -> Variant:
	match property:
		&"TotalTimePassed":
			return _total_time_passed
		&"CurrentDay":
			return _current_day
		&"PhaseProgress":
			return get_PhaseProgress()
	return null

## 处理跨越的每一个阶段，保持大步推进时的信号顺序。
func _check_time_transitions(old_points: int, new_points: int) -> void:
	var old_phase: int = old_points / PhaseLength
	var new_phase: int = new_points / PhaseLength
	for phase: int in range(old_phase + 1, new_phase + 1):
		IsNight = not IsNight
		DayNightToggled.emit(IsNight)
		if phase % 2 == 0:
			_current_day += 1
			DayPassed.emit(_current_day)
			if _current_day % 7 == 0:
				TalentSelectionTriggered.emit()

## 广播当前完整时间状态。
func _emit_time_changed() -> void:
	TimeChanged.emit(_total_time_passed, _current_day, IsNight, get_PhaseProgress(), PhaseLength)
