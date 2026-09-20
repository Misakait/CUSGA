extends Control

## 昼夜时间面板视图。
##
## 视图只读取 TimeSystem 的稳定属性与信号，不参与时间流逝或昼夜切换规则。

## TimeSystem 的阶段长度固定契约；视图保留同值用于首次快照刷新。
const PHASE_LENGTH: int = 100

## 当前项目的 TimeSystem Autoload；兼容生产 GDScript 与旧 C# 实现。
var _time_system: Node = null
## 展示当前天数的标签。
var _day_label: Label = null
## 展示白天或夜晚阶段的标签。
var _phase_label: Label = null
## 展示当前阶段进度文本的标签。
var _time_label: Label = null
## 展示当前阶段进度的进度条。
var _phase_progress: ProgressBar = null


## 解析视图节点，连接 TimeSystem，并显示当前时间快照。
## 返回值：无。
func _ready() -> void:
	_day_label = get_node("%DayLabel") as Label
	_phase_label = get_node("%PhaseLabel") as Label
	_time_label = get_node("%TimeLabel") as Label
	_phase_progress = get_node("%PhaseProgress") as ProgressBar
	_time_system = get_node_or_null("/root/TimeSystem") as Node
	if _time_system == null:
		push_error("TimePanelUI 未找到 TimeSystem Autoload。")
		return
	var callback := Callable(self, "_on_time_changed")
	if not _time_system.has_signal(&"TimeChanged"):
		push_error("TimePanelUI 需要 TimeSystem.TimeChanged 信号。")
		return
	if not _time_system.is_connected(&"TimeChanged", callback):
		_time_system.connect(&"TimeChanged", callback)
	_refresh(
		int(_time_system.get("CurrentDay")),
		bool(_time_system.get("IsNight")),
		int(_time_system.get("PhaseProgress")),
		PHASE_LENGTH
	)


## 退出场景树时解除 TimeSystem 信号，避免视图释放后保留回调。
## 返回值：无。
func _exit_tree() -> void:
	if _time_system == null:
		return
	var callback := Callable(self, "_on_time_changed")
	if _time_system.has_signal(&"TimeChanged") and _time_system.is_connected(&"TimeChanged", callback):
		_time_system.disconnect(&"TimeChanged", callback)
	_time_system = null


## 响应 TimeSystem 的完整时间快照并刷新视图。
## 参数 _total_time_passed：开局以来的总时间；旧视图同样不直接展示该值。
## 参数 current_day：当前天数。
## 参数 is_night：当前是否为夜晚。
## 参数 phase_progress：当前昼夜阶段内的进度。
## 参数 phase_length：本次快照对应的阶段长度。
## 返回值：无。
func _on_time_changed(
	_total_time_passed: int,
	current_day: int,
	is_night: bool,
	phase_progress: int,
	phase_length: int
) -> void:
	_refresh(current_day, is_night, phase_progress, phase_length)


## 把当前时间快照写入天数、阶段、进度文本和进度条。
## 参数 current_day：当前天数。
## 参数 is_night：当前是否为夜晚。
## 参数 phase_progress：当前阶段进度。
## 参数 phase_length：当前阶段总长度。
## 返回值：无。
func _refresh(current_day: int, is_night: bool, phase_progress: int, phase_length: int) -> void:
	_day_label.text = "第 %d 天" % current_day
	_phase_label.text = "夜晚" if is_night else "白天"
	_time_label.text = "%d / %d" % [phase_progress, phase_length]
	_phase_progress.min_value = 0
	_phase_progress.max_value = phase_length
	_phase_progress.value = phase_progress
