extends HBoxContainer

## 按键绑定行。
##
## 一行对应一个可重绑动作：左侧是动作中文名，右侧是显示当前键位的按钮。点击按钮后
## 进入「等待按键」状态，捕获到下一个键盘按键就把意图交给上层（UIOptionPanel），由
## KeyBindingManager 决定是否采纳。本组件不写 InputMap、不读本地设置，只负责显示与
## 收集输入，因此它的行为可以脱离 autoload 单独理解。

## 玩家完成一次按键捕获时发出。
## 参数 action：动作名。参数 event：捕获到的按键事件。
signal rebind_requested(action: StringName, event: InputEventKey)

## 玩家请求把本行动作恢复为项目默认键位时发出。
## 参数 action：动作名。
signal reset_requested(action: StringName)

## 与其它动作同键时，键位文案使用的红色。
const CONFLICT_COLOR: Color = Color(1.0, 0.35, 0.3)

## 等待按键期间按钮上显示的文案。
const LISTENING_TEXT: String = "请按下新键…"

## 冲突标红需要覆盖的全部按钮字体主题色。
##
## 只覆盖 `font_color` 会在悬停、按下或获得焦点时变回默认色，玩家恰好在这些状态下
## 看不出冲突，因此五种状态一起覆盖。
const FONT_COLOR_ITEMS: Array[StringName] = [
	&"font_color",
	&"font_hover_color",
	&"font_pressed_color",
	&"font_hover_pressed_color",
	&"font_focus_color",
]

## 按键绑定注册表脚本，提供键位文案格式化。
const KEY_BINDING_REGISTRY: GDScript = preload("res://core/input/key_binding_registry.gd")

@onready var _action_name_label: Label = %ActionName
@onready var _note_label: Label = %Note
@onready var _key_button: Button = %KeyButton
@onready var _reset_button: Button = %ResetButton

## 本行负责的动作名。
var _action: StringName = &""

## 最近一次由上层刷新的键位事件；取消等待时用它恢复按钮文案。
var _current_event: InputEvent = null

## 最近一次由上层刷新的冲突标记；取消等待时用它恢复红色状态。
var _is_conflicting: bool = false

## 是否正在等待玩家按键。
var _is_listening: bool = false

## setup() 在节点进入场景树之前被调用时，先暂存文案，等 `_ready()` 再落到控件上。
var _pending_display_name: String = ""
var _pending_note: String = ""


func _ready() -> void:
	_key_button.pressed.connect(_on_key_button_pressed)
	_reset_button.pressed.connect(_on_reset_button_pressed)
	set_process_input(false)
	_apply_static_text()


## 配置本行显示的动作。
##
## 允许在加入场景树之前或之后调用：控件引用是 `@onready` 的，过早落值会拿到 null，
## 因此这里先暂存文案，由 `_ready()` 负责真正写入。
## @param action 动作名。
## @param display_name 动作中文名。
## @param note 次要说明文案；为空时隐藏说明标签。
## @return void 无返回值。
func setup(action: StringName, display_name: String, note: String) -> void:
	_action = action
	_pending_display_name = display_name
	_pending_note = note
	if is_node_ready():
		_apply_static_text()


## 刷新当前键位文案、冲突标记与「恢复默认」按钮。
## @param event 当前生效的键位事件。
## @param is_conflicting 是否与其它动作同键。
## @param is_default 当前键位是否就是项目默认键位。
## @return void 无返回值。
func refresh(event: InputEvent, is_conflicting: bool, is_default: bool) -> void:
	_current_event = event
	_is_conflicting = is_conflicting
	_apply_reset_visibility(is_default)
	# 等待按键期间按钮正显示提示文案，此时刷新只更新数据，等捕获结束再落到界面上。
	if not _is_listening:
		_apply_key_text()


## 查询本行是否正在等待玩家按键。
## @return bool 正在等待返回 true。
func is_listening() -> bool:
	return _is_listening


## 取消等待按键状态。
##
## 上层在切走分类或收起面板时调用，避免留下一个仍在拦截键盘的行。
## @return void 无返回值。
func cancel_listening() -> void:
	if _is_listening:
		_stop_listening()


## 在等待按键期间捕获键盘输入。
##
## 用 `_input` 而不是 `_unhandled_input`：等待期间必须抢在暂停菜单等其它处理器之前
## 消费事件，否则按 ESC 会先弹出暂停菜单而不是取消本次改键。
## @param event 当前分发的输入事件。
## @return void 无返回值。
func _input(event: InputEvent) -> void:
	if not _is_listening:
		return

	var key_event: InputEventKey = event as InputEventKey
	if key_event == null:
		return

	# 键盘重复事件与抬起事件都不是一次新的绑定意图，但同样要吞掉，否则它们会漏给
	# 正在监听的其它系统（例如暂停菜单）。
	if key_event.echo or not key_event.pressed:
		get_viewport().set_input_as_handled()
		return

	if _is_cancel_key(key_event):
		_stop_listening()
		get_viewport().set_input_as_handled()
		return

	# 先结束等待再发信号：上层收到信号会同步刷新全部行，此时本行必须已经退出监听，
	# 否则刷新会被自己跳过，按钮停留在提示文案上。
	_stop_listening()
	rebind_requested.emit(_action, key_event)
	get_viewport().set_input_as_handled()


## 把暂存的动作名与说明文案写入控件。
## @return void 无返回值。
func _apply_static_text() -> void:
	_action_name_label.text = _pending_display_name
	_note_label.text = _pending_note
	_note_label.visible = not _pending_note.is_empty()


## 把当前键位与冲突状态写入按钮。
## @return void 无返回值。
func _apply_key_text() -> void:
	_key_button.text = String(KEY_BINDING_REGISTRY.call("format_event_text", _current_event))
	_apply_conflict_style(_is_conflicting)


## 按冲突状态设置或清除红色字体。
## @param is_conflicting 是否与其它动作同键。
## @return void 无返回值。
func _apply_conflict_style(is_conflicting: bool) -> void:
	for item: StringName in FONT_COLOR_ITEMS:
		if is_conflicting:
			_key_button.add_theme_color_override(item, CONFLICT_COLOR)
		else:
			_key_button.remove_theme_color_override(item)


## 判断按键事件是否为「取消改键」。
## @param event 待判断的键盘事件。
## @return bool ESC（逻辑键码或物理键码任一命中）返回 true。
func _is_cancel_key(event: InputEventKey) -> bool:
	return event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE


## 按「当前键位是否等于默认键位」显示或隐藏「恢复默认」按钮。
##
## 默认态不隐藏按钮，而是禁用并调成全透明：容器会跳过不可见子节点，直接 `visible = false`
## 会让本行重新排布，于是改过键的行与没改过的行键位列对不齐。禁用加透明既看不见也点不到，
## 同时保留占位。
## @param is_default 当前键位是否就是项目默认键位。
## @return void 无返回值。
func _apply_reset_visibility(is_default: bool) -> void:
	_reset_button.disabled = is_default
	_reset_button.modulate = Color(1, 1, 1, 0) if is_default else Color(1, 1, 1, 1)


## 把「恢复默认」按钮的一次点击转成恢复请求，具体还原由上层执行。
## @return void 无返回值。
func _on_reset_button_pressed() -> void:
	reset_requested.emit(_action)


## 进入等待按键状态。
## @return void 无返回值。
func _start_listening() -> void:
	_is_listening = true
	_key_button.text = LISTENING_TEXT
	set_process_input(true)


## 退出等待按键状态并恢复真实键位文案。
## @return void 无返回值。
func _stop_listening() -> void:
	_is_listening = false
	set_process_input(false)
	_apply_key_text()


## 把按钮的一次点击转换为进入或退出等待状态。
## @return void 无返回值。
func _on_key_button_pressed() -> void:
	if _is_listening:
		_stop_listening()
	else:
		_start_listening()
