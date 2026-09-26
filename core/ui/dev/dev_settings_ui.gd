extends Control

## 开发者设置面板。
##
## 面板提供一段隐藏的按键序列入口与若干调试开关，让开发者在不重启游戏、
## 不改动任何资源文件的前提下直接观察和改变当前对局状态。
##
## 它不自己保存任何游戏状态，而是把每次调整都交给该状态的既有持有者：天数与时间走
## TimeSystem 的公开协议，长按速度倍率走 WorldInteractionTiming 的换算规则。这样面板显示
## 与运行期生效值始终同源，也不会与时间流逝、昼夜切换这些权威规则产生分歧。
##
## 所有调试效果都通过「触发原本就会发生的流程」生效，而不是绕过它们。

## 触发本面板的固定按键序列。
const DEV_SEQUENCE: String = "LISBAM"

## 长按速度倍率控件的默认值：1 表示保持所有长按的原始等待时长。
const DEFAULT_HOLD_SPEED_MULTIPLIER: float = 1.0

## 长按速度倍率控件的下界，与 WorldInteractionTiming.MIN_HOLD_SPEED_MULTIPLIER 一致。
##
## 倍率在换算里是除数，取 0 会让等待时长变成无穷，因此这一侧的下界不是可调项。
const MIN_HOLD_SPEED_MULTIPLIER: float = 0.1

## 长按速度倍率控件的合法上界。
##
## 倍率越大长按越快，上界过大会让一次采集的等待短到看不清圆环，因此在这里收口。
const MAX_HOLD_SPEED_MULTIPLIER: float = 10.0

## TimeSystem 阶段长度的兜底值。
## 正常路径会从 TimeSystem 动态读取 PhaseLength，兜底只在协议读取失败时生效，
## 避免在面板里重复维护一份可能与时间系统脱节的常量。
const FALLBACK_PHASE_LENGTH: int = 100

## 等级系统 Autoload 的节点路径。
## 「增加一级」按钮靠它定位等级系统；面板不自持任何等级数值，避免与等级系统分叉。
const PLAYER_LEVEL_PATH: NodePath = ^"/root/PlayerLevel"

## 钱包 Autoload 的节点路径。
##
## 「获得金币」按钮靠它定位钱包，面板同样不自持任何金币数值。金币是存档参与者
## （key = player_wallet），加完金币由存档层按防抖自动落盘，面板不需要也不应该关心保存。
const PLAYER_WALLET_PATH: NodePath = ^"/root/PlayerWallet"

## 金币输入框的默认值。
const DEFAULT_GOLD_AMOUNT: int = 1000

## 金币输入框的合法上界。
##
## 刻意不等于钱包的 `MaxGold`（int 上限）：这是开发者调试入口而不是玩家输入，
## 一个够用又能一眼看出量级的上界比允许填 21 亿更好用。
const MAX_GOLD_AMOUNT: int = 999999

## 是否显示只对局内有意义的功能。
##
## 受它控制的是一组控件：当前天数、长按速度倍率、恢复默认、下一天、增加一级。它们都作用于
## 局内状态——等级每局重建、长按只发生在局内地图交互、天数属于本局时钟——摆在局外只会
## 给出无效效果。
##
## 由宿主场景决定：`Main.tscn` 保持默认 true（局内全套功能）；主菜单把它设为 false，
## 只留「获得金币」。刻意用导出开关，而不是让面板去嗅探自己挂在哪棵场景树上：面板不该
## 知道场景拓扑，而且这样能在测试里直接构造出两种模式。
@export var ShowRunFeatures: bool = true

## 承载本面板各控件的稳定子节点。
## 用唯一名而不是固定层级路径访问：既与 TimePanelUI 的既有惯例一致，
## 也让面板可以在测试里用最小节点树构造，不必复刻整棵场景层级。
@onready var _hold_speed_row: HBoxContainer = %HoldSpeedRow
@onready var _day_label: Label = %DayLabel
@onready var _hold_speed_spin_box: SpinBox = %HoldSpeedSpinBox
@onready var _next_day_button: Button = %NextDayButton
@onready var _reset_hold_speed_button: Button = %ResetHoldSpeedButton
@onready var _close_button: Button = %CloseButton
@onready var _level_up_button: Button = %LevelUpButton
@onready var _gold_spin_box: SpinBox = %GoldSpinBox
@onready var _gain_gold_button: Button = %GainGoldButton

## 时间系统 Autoload 的动态引用；缺失时面板功能整体禁用。
var _time_system: Node = null

## 等级系统 Autoload 的动态引用。
## 它只是「增加一级」按钮的依赖，缺失时只让该按钮静默无效，不拖累面板其余功能。
var _player_level: Node = null

## 钱包 Autoload 的动态引用。
## 与等级系统同理：缺失时只让「获得金币」静默无效，不拖累面板其余功能。
var _player_wallet: Node = null

## 序列匹配器实例。
## 匹配规则被拆到无场景依赖的 DevSequenceMatcher 中，因此可以在 tests 下独立断言。
var _matcher: DevSequenceMatcher = DevSequenceMatcher.new()

## 最近一次时间快照携带的阶段长度，用于在协议读取失败时保持可用。
var _phase_length: int = FALLBACK_PHASE_LENGTH

## 首次初始化是否已经完成。
##
## 用来区分两种「进入场景树」：首次进入时 `_enter_tree` 先于 `_ready` 触发，唯一名子节点
## 还没就绪，初始化必须留给 `_ready`；而被缓存复用的场景重新挂回时 `_ready` 不再触发，
## 只能由 `_enter_tree` 补做恢复。没有这个标记就无法区分二者。
var _is_initialized: bool = false


## 解析时间系统依赖，连接控件与信号，并同步一次当前状态。
## 返回值：无。
func _ready() -> void:
	hide()
	_configure_hold_speed_spin_box()
	_configure_gold_spin_box()
	_connect_buttons()

	# 等级系统与钱包都是可选依赖：面板其余功能在它们缺失时都能正常工作，因此这里不报错、
	# 也不提前返回，只在对应按钮被点击时静默跳过。
	_player_level = get_node_or_null(PLAYER_LEVEL_PATH)
	_player_wallet = get_node_or_null(PLAYER_WALLET_PATH)

	# 可见性必须先于 TimeSystem 的提前返回：局外模式（ShowRunFeatures = false）下
	# 面板本来就不依赖时间系统的任何控件，不该因为时间系统缺失而整组不生效。
	_apply_feature_visibility()

	# 标记首次初始化已完成：只有走到这里，唯一名子节点才保证可用，此后 _enter_tree 才有
	# 资格补做「缓存场景被重新挂回」时的恢复。
	_is_initialized = true

	if not _bind_time_system():
		push_error("DevSettingsUI 未找到 TimeSystem Autoload，开发者设置已禁用。")
		# 没有时间系统时序列入口没有任何可执行效果，直接停止监听未处理输入，
		# 避免面板成为只吞按键不办事的空壳。
		set_process_unhandled_input(false)


## 缓存场景被重新挂回时恢复时间系统绑定。
##
## 主菜单与仓库这两个宿主由 `SceneManager` 缓存复用：切走时只做 `remove_child`、切回时
## 直接 `add_child`，因此 `_ready` 不会再次执行，而 `_exit_tree` 已经断开订阅并把
## `_time_system` 置空。没有这一层恢复，第二次进入同一个缓存实例时「下一天」会静默失效
## （它的回调靠 `_time_system != null` 提前返回），且不报错。
##
## 长按速度倍率不受这条路径影响：它写的是 WorldInteractionTiming 的静态状态，与
## TimeSystem 无关，因此在缓存挂回后依然有效。
##
## 首次进入时必须让路：此时 `_ready` 还没跑，唯一名子节点尚未就绪，初始化只能由
## `_ready` 完成，所以用 `_is_initialized` 把这两种时机区分开。
## 返回值：无。
func _enter_tree() -> void:
	if not _is_initialized:
		return

	# 必须重新解析引用，而不只是重连信号：_exit_tree 已经把 _time_system 置空，
	# 只恢复订阅会让面板一直停在一个空引用上。失败时保持失效即可，装配错误已由
	# _ready 报过一次，这里不再重复刷屏。
	_bind_time_system()


## 解析时间系统，并立刻订阅快照信号、同步一次显示。
##
## 抽成独立方法是为了让 `_ready`（首次进入）与 `_enter_tree`（缓存挂回）共用同一条
## 「解析 → 订阅 → 同步」路径，避免两处实现漂移。
## 返回值：绑定成功时为 true；时间系统缺失时为 false。
func _bind_time_system() -> bool:
	_time_system = get_node_or_null("/root/TimeSystem") as Node
	if _time_system == null:
		return false

	_phase_length = _read_phase_length()
	_connect_time_system()
	_sync_from_time_system()
	return true


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
	_sync_hold_speed_from_multiplier()
	show()


## 关闭面板，并释放数值控件的键盘焦点。
##
## 释放焦点是必要的：SpinBox 会消费自己持有的按键，若焦点残留在隐藏的控件上，
## 之后的 LISBAM 序列将无法到达本面板的未处理输入回调。
## 返回值：无。
func _on_close_button_pressed() -> void:
	hide()
	_hold_speed_spin_box.release_focus()
	_gold_spin_box.release_focus()


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


## 给玩家提升一级，用于免去反复刷经验去观察等级相关表现。
##
## 走等级系统的公开接口 AddLevels，而不是直接改写等级字段：AddLevels 复用完整的升级
## 结算（逐级发出 LevelChanged 并累计待领属性点），直接写字段会让属性点与信号订阅方
## 同等级脱节。
## 返回值：无。
func _on_level_up_button_pressed() -> void:
	if _player_level == null or not _player_level.has_method("AddLevels"):
		return

	_player_level.call("AddLevels", 1)


## 把输入框里的数量加进钱包。
##
## 走钱包的公开接口 Add，而不是直接改写余额字段：Add 负责夹紧到 int 上限并发出
## GoldChanged，直接写字段会让余额显示与存档层都收不到这次变化。
##
## 加完金币的落盘由存档层按防抖统一决定（钱包是存档参与者），面板不触发也不关心保存。
## 返回值：无。
func _on_gain_gold_button_pressed() -> void:
	if _player_wallet == null or not _player_wallet.has_method("Add"):
		return

	_player_wallet.call("Add", int(_gold_spin_box.value))


## 把长按速度倍率恢复为默认值。
##
## 恢复的是面板自己的控件值，写回换算规则由控件的 value_changed 信号完成，
## 因此这里不必也不应直接调用 WorldInteractionTiming。
## 返回值：无。
func _on_reset_hold_speed_button_pressed() -> void:
	_hold_speed_spin_box.value = DEFAULT_HOLD_SPEED_MULTIPLIER


## 把控件里的倍率写入长按换算规则。
##
## 与其它控件不同，这一步不经过 TimeSystem：倍率只压缩长按的等待时长，不改动任何行动值
## 扣费，因此它作为换算规则上的系数写在 WorldInteractionTiming 的静态状态里。
##
## 参数 value：SpinBox 当前值；控件已按 min/max 夹紧，换算规则侧还会再兜一次非法值。
## 返回值：无。
func _on_hold_speed_spin_box_value_changed(value: float) -> void:
	WorldInteractionTiming.set_hold_speed_multiplier(value)


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


## 刷新天数标签文本。
## 参数 current_day：需要展示的当前天数。
## 返回值：无。
func _refresh_day_label(current_day: int) -> void:
	_day_label.text = "当前天数：%d" % current_day


## 用当前生效的倍率刷新控件显示。
##
## 必须从换算规则回填，而不是只在脚本里写死初始值：倍率的权威是那份静态状态，别处可能
## 已经改过它，面板显示与实际生效值不一致会让开发者误判自己的调整到底有没有生效。
## 回填走 set_value_no_signal，避免回填动作本身又被当成一次玩家改动写回去。
## 返回值：无。
func _sync_hold_speed_from_multiplier() -> void:
	_hold_speed_spin_box.set_value_no_signal(
		clampf(
			WorldInteractionTiming.get_hold_speed_multiplier(),
			MIN_HOLD_SPEED_MULTIPLIER,
			MAX_HOLD_SPEED_MULTIPLIER
		)
	)


## 配置长按速度倍率控件的合法取值范围并填入默认倍率。
## 返回值：无。
func _configure_hold_speed_spin_box() -> void:
	_hold_speed_spin_box.min_value = MIN_HOLD_SPEED_MULTIPLIER
	_hold_speed_spin_box.max_value = MAX_HOLD_SPEED_MULTIPLIER
	_hold_speed_spin_box.step = 0.1
	_hold_speed_spin_box.value = DEFAULT_HOLD_SPEED_MULTIPLIER
	# 显式关闭越界放行，让非法输入在控件层就被夹紧，而不是留给下游判断。
	_hold_speed_spin_box.allow_greater = false
	_hold_speed_spin_box.allow_lesser = false


## 把金币输入框限制在既定范围内并填入默认数量。
##
## 与倍率控件同一套做法：范围在场景里也写了一遍（供编辑器预览），这里再收口一次，
## 避免改场景时只改了一半；越界放行同样关闭，让非法输入在控件层就被夹紧。
##
## 与倍率控件不同的是，这里连初始值也由脚本写死：金币输入框是「要加多少」的一次性数量，
## 不镜像任何外部状态（倍率控件会从换算规则回填），因此常量必须是唯一的权威来源。
## 返回值：无。
func _configure_gold_spin_box() -> void:
	_gold_spin_box.min_value = 1
	_gold_spin_box.max_value = MAX_GOLD_AMOUNT
	_gold_spin_box.step = 1
	_gold_spin_box.value = DEFAULT_GOLD_AMOUNT
	_gold_spin_box.allow_greater = false
	_gold_spin_box.allow_lesser = false


## 按 ShowRunFeatures 决定局内专属控件的可见性。
##
## 隐藏的是整行而不是单个输入框：长按速度倍率那一行的说明文字与输入框分属两个节点，
## 只藏输入框会留下一句没有对应控件的标签。
## 返回值：无。
func _apply_feature_visibility() -> void:
	var run_only_rows: Array[CanvasItem] = [
		_day_label,
		_hold_speed_row,
		_reset_hold_speed_button,
		_next_day_button,
		_level_up_button,
	]
	for row: CanvasItem in run_only_rows:
		row.visible = ShowRunFeatures


## 连接面板自有控件的信号。
## 返回值：无。
func _connect_buttons() -> void:
	_next_day_button.pressed.connect(_on_next_day_button_pressed)
	_level_up_button.pressed.connect(_on_level_up_button_pressed)
	_reset_hold_speed_button.pressed.connect(_on_reset_hold_speed_button_pressed)
	_close_button.pressed.connect(_on_close_button_pressed)
	_gain_gold_button.pressed.connect(_on_gain_gold_button_pressed)
	_hold_speed_spin_box.value_changed.connect(_on_hold_speed_spin_box_value_changed)


## 连接时间系统的完整快照信号。
## 返回值：无。
func _connect_time_system() -> void:
	if not _time_system.has_signal(&"TimeChanged"):
		push_error("DevSettingsUI 需要 TimeSystem.TimeChanged 信号。")
		return

	var callback := Callable(self, "_on_time_changed")
	if not _time_system.is_connected(&"TimeChanged", callback):
		_time_system.connect(&"TimeChanged", callback)
