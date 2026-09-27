extends CanvasLayer

## 全屏大地图协调器。
##
## 根节点只协调可配置输入动作、暂停所有权、当前房间聚焦和标记意图。拖拽缩放交给
## ViewportControl，标记选项交给 LegendUI，标记事实仍由 MapWorldModel 管理。

const CURRENT_ROOM_CHANGED_SIGNAL: StringName = &"current_room_changed"

## 右键删除玩家标记时允许命中的逻辑地图半径。
@export_range(0.01, 2.0, 0.01) var marker_delete_radius: float = 0.35

var _map_model: Node = null
var _was_paused_before_open: bool = false
var _owns_open_state: bool = false

@onready var viewport_control: Control = $ViewportControl
@onready var map_canvas: Control = $ViewportControl/WorldMapCanvas
@onready var legend_ui: Control = $LegendUI


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var resized_callable := Callable(self, "focus_current_room")
	if not viewport_control.is_connected(&"resized", resized_callable):
		viewport_control.connect(&"resized", resized_callable)
	if viewport_control.has_signal(&"canvas_left_clicked"):
		viewport_control.connect(&"canvas_left_clicked", _on_canvas_left_clicked)
	if viewport_control.has_signal(&"canvas_right_clicked"):
		viewport_control.connect(&"canvas_right_clicked", _on_canvas_right_clicked)


func _exit_tree() -> void:
	_restore_pause_if_owned()
	_disconnect_model()


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event != null and key_event.echo:
		return
	if not event.is_action_pressed("open_map"):
		return
	var map_owner := get_parent() as CanvasItem
	if map_owner != null and not map_owner.visible:
		return
	toggle_map()
	get_viewport().set_input_as_handled()


## 绑定地图 Model，并把同一 Model 传给内部 WorldMapCanvas。
##
## @param model 地图世界 Model。
## @return 画布与信号都绑定成功时返回 true。
func bind_model(model: Node) -> bool:
	if model == _map_model:
		focus_current_room()
		return model != null
	_disconnect_model()
	if (
		model == null
		or not model.has_signal(CURRENT_ROOM_CHANGED_SIGNAL)
		or not model.has_method(&"add_player_marker")
		or not model.has_method(&"remove_nearest_player_marker")
	):
		push_error("UILargeMap 收到的 Model 缺少大地图交互协议。")
		return false
	if not map_canvas.has_method(&"bind_model") or not bool(map_canvas.call(&"bind_model", model)):
		push_error("UILargeMap 无法绑定内部 WorldMapCanvas。")
		return false
	_map_model = model
	var callable := Callable(self, "_on_current_room_changed")
	if not _map_model.is_connected(CURRENT_ROOM_CHANGED_SIGNAL, callable):
		_map_model.connect(CURRENT_ROOM_CHANGED_SIGNAL, callable)
	return true


## 显示大地图、取得暂停所有权并聚焦当前房间。
##
## @return 无返回值。
func show_map() -> void:
	if visible:
		return
	var tree := get_tree()
	_was_paused_before_open = tree.paused
	_owns_open_state = true
	tree.paused = true
	visible = true
	call_deferred("focus_current_room")


## 隐藏大地图，并只归还本次打开造成的暂停。
##
## @return 无返回值。
func hide_map() -> void:
	if not visible and not _owns_open_state:
		return
	visible = false
	_restore_pause_if_owned()


## 切换大地图显示状态。
##
## @return 无返回值。
func toggle_map() -> void:
	if visible:
		hide_map()
	else:
		show_map()


## 把当前房间移动到大地图可视区域中心。
##
## @return 无返回值。
func focus_current_room() -> void:
	if _map_model == null or not map_canvas.has_method(&"get_room_canvas_position"):
		return
	var current_value: Variant = _map_model.get(&"current_position")
	if not current_value is Vector2i:
		return
	var room_position: Vector2 = map_canvas.call(&"get_room_canvas_position", current_value)
	if viewport_control.has_method(&"focus_canvas_position"):
		viewport_control.call(&"focus_canvas_position", room_position)


func _on_canvas_left_clicked(canvas_position: Vector2) -> void:
	if _map_model == null or not map_canvas.has_method(&"canvas_position_to_logical"):
		return
	var selected_config: Resource = null
	if legend_ui.has_method(&"get_selected_config"):
		selected_config = legend_ui.call(&"get_selected_config") as Resource
	if selected_config == null:
		return
	var logical_position: Vector2 = map_canvas.call(&"canvas_position_to_logical", canvas_position)
	_map_model.call(&"add_player_marker", selected_config, logical_position)


func _on_canvas_right_clicked(canvas_position: Vector2) -> void:
	if _map_model == null or not map_canvas.has_method(&"canvas_position_to_logical"):
		return
	var logical_position: Vector2 = map_canvas.call(&"canvas_position_to_logical", canvas_position)
	_map_model.call(&"remove_nearest_player_marker", logical_position, marker_delete_radius)


func _on_current_room_changed(_position: Vector2i) -> void:
	if visible:
		focus_current_room()


func _restore_pause_if_owned() -> void:
	if not _owns_open_state:
		return
	_owns_open_state = false
	var tree := get_tree()
	if tree != null and not _was_paused_before_open:
		tree.paused = false


func _disconnect_model() -> void:
	if _map_model == null or not is_instance_valid(_map_model):
		_map_model = null
		return
	var callable := Callable(self, "_on_current_room_changed")
	if (
		_map_model.has_signal(CURRENT_ROOM_CHANGED_SIGNAL)
		and _map_model.is_connected(CURRENT_ROOM_CHANGED_SIGNAL, callable)
	):
		_map_model.disconnect(CURRENT_ROOM_CHANGED_SIGNAL, callable)
	_map_model = null
