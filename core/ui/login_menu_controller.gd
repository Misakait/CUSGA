## 登录菜单控制器，只协调菜单选择、键盘焦点与已有功能入口。
extends Control

const MAIN_SCENE_PATH: String = "res://scenes/Main.tscn"
const MOTION = preload("res://core/ui/transitions/ui_transition.gd")

## 开始界面的确认动作名。
##
## 项目里这个动作的历史命名是 `check`，语义就是「确认」。这里刻意不读引擎内置的
## `ui_accept`：内置动作由 Control 焦点系统直接消费，不受 `InputMap` 里的玩家改键控制，
## 读它等于确认键永远改不掉。
const CONFIRM_ACTION: StringName = &"check"

var _buttons: Array[Button] = []
var _pressed_callables: Array[Callable] = []
var _selection_callables: Array[Callable] = []
var _back_callable: Callable
var _selected_index: int = 0
var _settings_open: bool = false
var _transition_pending: bool = false
var _menu_motion: MOTION
var _options_motion: MOTION
var _ui_entered: bool = false

@onready var _menu_column: Control = %MenuColumn
@onready var _option_panel: Control = %OptionPanel
@onready var _start_button: Button = %StartButton
@onready var _settings_button: Button = %SettingsButton
@onready var _warehouse_button: Button = %WarehouseButton
@onready var _exit_button: Button = %ExitButton
@onready var _dev_settings_ui: Control = $DevSettingsUI


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_buttons = [_start_button, _settings_button, _warehouse_button, _exit_button]
	for index: int in _buttons.size():
		_pressed_callables.append(_on_button_pressed.bind(_buttons[index]))
		_selection_callables.append(_on_button_selected.bind(index))
	_back_callable = _on_option_panel_back_requested
	init()
	_play_initial_ui_enter.call_deferred()


## 恢复菜单显示、信号和当前选择，供 SceneManager 缓存重入调用。
## 无参数；返回无。
func init() -> void:
	if not is_inside_tree() or _buttons.is_empty():
		return
	_transition_pending = false
	_settings_open = false
	_set_connections(true)
	_option_panel.hide()
	_menu_column.show()
	for button: Button in _buttons:
		button.disabled = false
	_select_index(_selected_index, true)
	# 刚挂回树时容器和视口焦点尚在恢复，下一次空闲帧再确认一次选择。
	_restore_menu_focus.call_deferred()


func _exit_tree() -> void:
	_set_connections(false)
	_ui_entered = false
	if is_instance_valid(_menu_motion):
		_menu_motion.reset()
	if is_instance_valid(_options_motion):
		_options_motion.reset()


## 播放主菜单入场。参数 completed 为入场完成回调；返回无。
func play_ui_enter(completed: Callable = Callable()) -> void:
	_setup_motion()
	_ui_entered = true
	_transition_pending = true
	_settings_open = false
	_options_motion.reset()
	_option_panel.hide()
	_menu_column.show()
	_menu_motion.play_open(_finish_ui_enter.bind(completed))


## 播放当前菜单页退场。参数 completed 为退场完成回调；返回无。
func play_ui_exit(completed: Callable = Callable()) -> void:
	_setup_motion()
	_transition_pending = true
	# 动画期间释放焦点，防止原生确认键绕过鼠标遮罩重复触发按钮。
	get_viewport().gui_release_focus()
	var active_motion: MOTION = _options_motion if _settings_open else _menu_motion
	active_motion.play_close(completed)


func _setup_motion() -> void:
	if is_instance_valid(_menu_motion):
		return
	_menu_motion = MOTION.new()
	add_child(_menu_motion)
	# Center 的父节点不参与容器排版；只变形整列菜单，不争抢按钮的布局位置。
	_menu_motion.setup([get_node("Center") as CanvasItem], 0.0, 0.24, 0.0, MOTION.MotionStyle.RISE)
	_options_motion = MOTION.new()
	add_child(_options_motion)
	_options_motion.setup([_option_panel], 0.015, 0.20, 0.0, MOTION.MotionStyle.SOFT_SCALE)


func _play_initial_ui_enter() -> void:
	# SceneManager 在首次 add_child 后也会请求入场，此标记避免两条入口叠播。
	if is_inside_tree() and not _ui_entered:
		play_ui_enter()


func _finish_ui_enter(completed: Callable) -> void:
	if not is_inside_tree():
		return
	_transition_pending = false
	_restore_menu_focus()
	if completed.is_valid():
		completed.call()


func _set_connections(connect_signals: bool) -> void:
	# 保存并复用同一 Callable，移出缓存场景时断开，重入时不会累积连接。
	for index: int in _buttons.size():
		var button: Button = _buttons[index]
		_update_connection(button.pressed, _pressed_callables[index], connect_signals)
		_update_connection(button.mouse_entered, _selection_callables[index], connect_signals)
		_update_connection(button.focus_entered, _selection_callables[index], connect_signals)
	if is_instance_valid(_option_panel):
		_update_connection(Signal(_option_panel, &"back_requested"), _back_callable, connect_signals)


func _update_connection(source: Signal, callback: Callable, connect_signal: bool) -> void:
	if connect_signal and not source.is_connected(callback):
		source.connect(callback)
	elif not connect_signal and source.is_connected(callback):
		source.disconnect(callback)


func _input(event: InputEvent) -> void:
	if _transition_pending:
		get_viewport().set_input_as_handled()
		return
	if _settings_open or _dev_settings_ui.visible:
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	# 确认键和 W/S 一样只由 InputMap 决定，玩家在按键设置里改键即可生效。
	#
	# 原生 Button 会在 _gui_input 阶段抢先用引擎内置的 ui_accept 触发 pressed，那条路径不查
	# check。所以这里用 _input（它排在 _gui_input 之前）先把 ui_accept 整个吞掉，让确认只剩
	# check 一条路径；否则改键后按新键会确认、按旧键（回车/空格）也会确认，等于没改。
	if event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
	if event.is_action_pressed(&"move_up"):
		_select_index(_selected_index - 1, true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"move_down"):
		_select_index(_selected_index + 1, true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(CONFIRM_ACTION):
		get_viewport().set_input_as_handled()
		_buttons[_selected_index].pressed.emit()


func _on_button_selected(index: int) -> void:
	if not _settings_open and not _transition_pending:
		_select_index(index, true)


func _on_button_pressed(button: Button) -> void:
	if _settings_open or _transition_pending:
		return
	var index: int = _buttons.find(button)
	if index < 0:
		return
	_select_index(index, true)
	match index:
		0:
			_start_game()
		1:
			_open_settings()
		2:
			_open_warehouse()
		3:
			get_tree().quit()


func _select_index(index: int, focus_button: bool) -> void:
	_selected_index = posmod(index, _buttons.size())
	# 先释放其他按钮，再按下当前按钮，保证任何中间状态也不会多选。
	for button_index: int in _buttons.size():
		if button_index != _selected_index:
			_buttons[button_index].set_pressed_no_signal(false)
	_buttons[_selected_index].set_pressed_no_signal(true)
	if focus_button and not _buttons[_selected_index].has_focus():
		_buttons[_selected_index].grab_focus()


func _restore_menu_focus() -> void:
	if is_inside_tree() and not _settings_open and not _transition_pending:
		_select_index(_selected_index, true)


func _start_game() -> void:
	play_ui_exit(_commit_start_game)


func _commit_start_game() -> void:
	var error: Error = get_tree().change_scene_to_file(MAIN_SCENE_PATH)
	if error != OK:
		play_ui_enter()
		push_error("登录菜单：无法加载开始游戏场景，错误码 %s。" % error)


func _open_settings() -> void:
	_setup_motion()
	_transition_pending = true
	_settings_open = true
	get_viewport().gui_release_focus()
	_menu_motion.play_close(_show_settings)


func _show_settings() -> void:
	_menu_column.hide()
	_option_panel.show()
	if _option_panel.has_method(&"refresh_from_settings"):
		_option_panel.call(&"refresh_from_settings")
	_options_motion.play_open(_finish_settings_enter)


func _finish_settings_enter() -> void:
	_transition_pending = false
	var back_button: Control = _option_panel.get_node_or_null("%BackButton") as Control
	if back_button != null:
		back_button.grab_focus()


func _on_option_panel_back_requested() -> void:
	if _transition_pending or not _settings_open:
		return
	_transition_pending = true
	get_viewport().gui_release_focus()
	_options_motion.play_close(play_ui_enter)


func _open_warehouse() -> void:
	var event_bus: Node = get_node_or_null(^"/root/GlobalEventBus")
	if event_bus == null or not event_bus.has_signal(&"scene_requested"):
		push_error("登录菜单：找不到 GlobalEventBus，无法打开游戏仓库。")
		return
	# 仓库切换需要等待退场，等待期间禁止再次确认，避免并发切换同一场景。
	_transition_pending = true
	event_bus.emit_signal(&"scene_requested", "warehouse")
