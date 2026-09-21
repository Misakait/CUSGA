extends Control

## 开发者设置面板。
##
## 面板提供一段隐藏的按键序列入口与若干调试开关，让开发者在不重启游戏、
## 不改动任何资源文件的前提下直接观察和改变当前对局状态。
##
## 它只调用 TimeSystem 的既有公开协议，不参与时间流逝或昼夜切换规则本身，
## 因此不会与时间系统的权威状态产生分歧；所有调试效果都通过「触发原本就会
## 发生的流程」生效，而不是绕过它们。

## 触发本面板的固定按键序列。
const DEV_SEQUENCE: String = "LISBAM"

## 行动值消耗控件的默认值，与 TimeSystem.MapMoveTimeCost 的导出默认值保持一致。
const DEFAULT_ACTION_COST: int = 10

## 行动值消耗控件的合法上界。
## 行动值按「每 10 点 = 1 秒」换算成长按等待时长（core/constants/world_interaction_timing.gd），
## 上界过大会让一次采集的等待时间变得不可用，因此在这里收口。
const MAX_ACTION_COST: int = 999

## TimeSystem 阶段长度的兜底值。
## 正常路径会从 TimeSystem 动态读取 PhaseLength，兜底只在协议读取失败时生效，
## 避免在面板里重复维护一份可能与时间系统脱节的常量。
const FALLBACK_PHASE_LENGTH: int = 100

## 承载本面板各控件的稳定子节点。
## 用唯一名而不是固定层级路径访问：既与 TimePanelUI 的既有惯例一致，
## 也让面板可以在测试里用最小节点树构造，不必复刻整棵场景层级。
@onready var _day_label: Label = %DayLabel
@onready var _cost_spin_box: SpinBox = %CostSpinBox
@onready var _next_day_button: Button = %NextDayButton
@onready var _reset_cost_button: Button = %ResetCostButton
@onready var _close_button: Button = %CloseButton

## 时间系统 Autoload 的动态引用；缺失时面板功能整体禁用。
var _time_system: Node = null

## 序列匹配器实例。
## 匹配规则被拆到无场景依赖的 DevSequenceMatcher 中，因此可以在 tests 下独立断言。
var _matcher: DevSequenceMatcher = DevSequenceMatcher.new()

## 最近一次时间快照携带的阶段长度，用于在协议读取失败时保持可用。
var _phase_length: int = FALLBACK_PHASE_LENGTH


## 解析时间系统依赖，连接控件与信号，并同步一次当前状态。
## 返回值：无。
func _ready() -> void:
	hide()
	_configure_cost_spin_box()
	_connect_buttons()

	_time_system = get_node_or_null("/root/TimeSystem") as Node
	if _time_system == null:
		push_error("DevSettingsUI 未找到 TimeSystem Autoload，开发者设置已禁用。")
		# 没有时间系统时序列入口没有任何可执行效果，直接停止监听未处理输入，
		# 避免面板成为只吞按键不办事的空壳。
		set_process_unhandled_input(false)
		return

	_phase_length = _read_phase_length()
	_connect_time_system()
	_sync_from_time_system()


## 退出场景树时解除 TimeSystem 信号，避免面板释放后仍保留回调。
## 返回值：无。
func _exit_tree() -> void:
	if _time_system == null:
		return

	var callback := Callable(self, "_on_time_changed")
	if _time_system.has_signal(&"TimeChanged") and _time_system.is_connected(&"TimeChanged", callback):
		_time_system.disconnect(&"TimeChanged", callback)
	_time_system = null


## 在未处理输入阶段累积隐藏序列。
##
## 刻意不调用 get_viewport().set_input_as_handled()：序列监听对既有输入系统
## 必须完全透明，否则会吞掉背包、合成等快捷键，也会干扰文本输入控件。
## 参数 event：尚未被其他节点消费的输入事件。
## 返回值：无。
func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null:
		return

	var letter: String = _resolve_letter(key_event)
	if letter.is_empty():
		return

	if _matcher.push_letter(letter):
		_open_panel()


## 从一次按键事件中解析出用于匹配的单个大写字母。
##
## 物理键位优先：它不受 Shift、CapsLock 与输入法状态影响，隐藏序列因此更可靠；
## 仅在物理键位解析不出字母时，才回退到本次输入的字符码。
##
## 参数 event：待解析的按键事件。
## 返回值：单个大写字母；非字母键、长按重复或松开事件返回空字符串。
func _resolve_letter(event: InputEventKey) -> String:
	if not event.pressed or event.echo:
		return ""

	var physical_letter: String = _extract_ascii_letter(OS.get_keycode_string(event.physical_keycode))
	if not physical_letter.is_empty():
		return physical_letter

	if event.unicode != 0:
		return _extract_ascii_letter(String.chr(event.unicode))

	return ""


## 把任意文本归一化为单个大写字母。
## 参数 text：待归一化的文本，通常来自键位名或字符码。
## 返回值：单个大写字母；不是单个 ASCII 字母时返回空字符串。
func _extract_ascii_letter(text: String) -> String:
	if text.length() != 1:
		return ""

	# 只接受 A-Z / a-z，避免数字键、功能键或控制字符污染序列进度。
	var code: int = text.unicode_at(0)
	if (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
		return text.to_upper()

	return ""


## 打开面板并同步一次当前状态。
##
## 重复调用是幂等的：show() 不会创建第二个面板，符合「窗口已打开时再次输入
## 完整序列应保持打开」的预期。
## 返回值：无。
func _open_panel() -> void:
	_sync_from_time_system()
	show()


## 关闭面板，并释放数值控件的键盘焦点。
##
## 释放焦点是必要的：SpinBox 会消费自己持有的按键，若焦点残留在隐藏的控件上，
## 之后的 LISBAM 序列将无法到达本面板的未处理输入回调。
## 返回值：无。
func _on_close_button_pressed() -> void:
	hide()
	_cost_spin_box.release_focus()


## 把时间推进到下一个天数边界的起点（第二天白天）。
## 返回值：无。
func _on_next_day_button_pressed() -> void:
	if _time_system == null:
		return

	var points: int = _get_points_to_next_day()
	if points <= 0:
		return

	# 必须走 PassTime：它负责按既有顺序发出昼夜切换、天数增加与天赋选择信号，
	# 直接改写 _current_day 会让依赖这些信号的世界状态与天数脱节。
	_time_system.call("PassTime", points)


## 把行动值消耗控件恢复为默认值。
## 返回值：无。
func _on_reset_cost_button_pressed() -> void:
	_cost_spin_box.value = DEFAULT_ACTION_COST


## 把控件数值写入时间系统。
## 参数 value：SpinBox 当前值；控件本身已按 min/max 夹紧，这里再取整一次。
## 返回值：无。
func _on_cost_spin_box_value_changed(value: float) -> void:
	if _time_system == null:
		return

	# SetMapMoveTimeCost 自带 amount > 0 守卫，构成 SpinBox 夹紧之外的第二道防线。
	_time_system.call("SetMapMoveTimeCost", int(value))


## 响应 TimeSystem 的完整时间快照并刷新显示。
## 参数 _total_time_passed：开局以来的总时间；面板不展示该值。
## 参数 current_day：当前天数。
## 参数 _is_night：当前是否为夜晚；面板不展示昼夜。
## 参数 _phase_progress：当前阶段内的进度；面板不展示该值。
## 参数 phase_length：本次快照对应的阶段长度。
## 返回值：无。
func _on_time_changed(
	_total_time_passed: int,
	current_day: int,
	_is_night: bool,
	_phase_progress: int,
	phase_length: int
) -> void:
	_phase_length = maxi(phase_length, 1)
	_refresh_day_label(current_day)


## 计算推进到下一个天数边界所需的行动值点数。
##
## TimeSystem 只在跨过「偶数阶段」时才把天数加一（core/autoloads/time_system.gd
## 的 _check_time_transitions），一天恰好是白天与夜晚两个阶段，因此「下一天」
## 等价于推进到下一个偶数阶段边界的起点。
##
## 返回值：需要增加的行动值点数；始终为正数，保证推进一定跨过天数边界。
func _get_points_to_next_day() -> int:
	var total: int = int(_time_system.get("TotalTimePassed"))
	var phase_length: int = _read_phase_length()
	var current_phase: int = total / phase_length
	var next_even_phase: int = current_phase + 1
	if next_even_phase % 2 != 0:
		next_even_phase += 1

	return next_even_phase * phase_length - total


## 从时间系统读取阶段长度。
## 返回值：时间系统当前的 PhaseLength；协议不可用时返回兜底值。
func _read_phase_length() -> int:
	if _time_system == null:
		return FALLBACK_PHASE_LENGTH

	var value: Variant = _time_system.get("PhaseLength")
	if value is int and int(value) > 0:
		return int(value)
	if value is float and float(value) > 0.0:
		return int(value)

	return FALLBACK_PHASE_LENGTH


## 用时间系统的当前状态刷新面板显示。
## 返回值：无。
func _sync_from_time_system() -> void:
	if _time_system == null:
		return

	_phase_length = _read_phase_length()
	_refresh_day_label(int(_time_system.get("CurrentDay")))

	# 用 set_value_no_signal 回填：打开面板只做展示，不应把当前值再写回时间系统，
	# 否则会与「只在玩家改动时才写入」的契约相冲突。
	var current_cost: int = int(_time_system.get("MapMoveTimeCost"))
	_cost_spin_box.set_value_no_signal(clampi(current_cost, 1, MAX_ACTION_COST))


## 刷新天数标签文本。
## 参数 current_day：需要展示的当前天数。
## 返回值：无。
func _refresh_day_label(current_day: int) -> void:
	_day_label.text = "当前天数：%d" % current_day


## 配置行动值消耗控件的合法取值范围。
## 返回值：无。
func _configure_cost_spin_box() -> void:
	_cost_spin_box.min_value = 1
	_cost_spin_box.max_value = MAX_ACTION_COST
	_cost_spin_box.step = 1
	# 显式关闭越界放行，让非法输入在控件层就被夹紧，而不是留给下游判断。
	_cost_spin_box.allow_greater = false
	_cost_spin_box.allow_lesser = false


## 连接面板自有控件的信号。
## 返回值：无。
func _connect_buttons() -> void:
	_next_day_button.pressed.connect(_on_next_day_button_pressed)
	_reset_cost_button.pressed.connect(_on_reset_cost_button_pressed)
	_close_button.pressed.connect(_on_close_button_pressed)
	_cost_spin_box.value_changed.connect(_on_cost_spin_box_value_changed)


## 连接时间系统的完整快照信号。
## 返回值：无。
func _connect_time_system() -> void:
	if not _time_system.has_signal(&"TimeChanged"):
		push_error("DevSettingsUI 需要 TimeSystem.TimeChanged 信号。")
		return

	var callback := Callable(self, "_on_time_changed")
	if not _time_system.is_connected(&"TimeChanged", callback):
		_time_system.connect(&"TimeChanged", callback)
