extends CanvasLayer

## 全屏大地图协调器。
##
## 根节点只协调可配置输入动作、暂停所有权、当前房间聚焦和标记意图。拖拽缩放交给
## ViewportControl，标记选项交给 LegendUI，标记事实仍由 MapWorldModel 管理。

const CURRENT_ROOM_CHANGED_SIGNAL: StringName = &"current_room_changed"
const JELLY_MOTION: GDScript = preload("res://core/ui/transitions/ui_transition.gd")
const PAUSE_OWNERS_GROUP: StringName = &"ui_pause_owners"
const PAUSE_HANDOFF_METHOD: StringName = &"take_pause_release_ownership"

## 右键删除玩家标记时允许命中的逻辑地图半径。
@export_range(0.01, 2.0, 0.01) var marker_delete_radius: float = 0.35

var _map_model: Node = null
## 打开前的暂停状态；从其它界面接手恢复责任时改为 false。
var _was_paused_before_open: bool = false
var _owns_open_state: bool = false
var _motion: JELLY_MOTION = null

@onready var viewport_control: Control = $ViewportControl
@onready var map_canvas: Control = $ViewportControl/WorldMapCanvas
@onready var legend_ui: Control = $LegendUI


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(PAUSE_OWNERS_GROUP)
	visible = false
	_motion = JELLY_MOTION.new()
	_motion.name = "MapJellyTransition"
	add_child(_motion)
	# 大地图只淡入，避免外层缩放带动整张地图，影响阅读和拖拽定位。
	var motion_targets: Array[CanvasItem] = [$FrameBackground, viewport_control, legend_ui]
	_motion.setup(motion_targets, 0.0, 0.20, 0.0, JELLY_MOTION.MotionStyle.FADE)
	var resized_callable := Callable(self, "focus_current_room")
	if not viewport_control.is_connected(&"resized", resized_callable):
		viewport_control.connect(&"resized", resized_callable)
	if viewport_control.has_signal(&"canvas_left_clicked"):
		viewport_control.connect(&"canvas_left_clicked", _on_canvas_left_clicked)
	if viewport_control.has_signal(&"canvas_right_clicked"):
		viewport_control.connect(&"canvas_right_clicked", _on_canvas_right_clicked)


func _exit_tree() -> void:
	if is_instance_valid(_motion):
		_motion.reset()
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


## 显示大地图、取得暂停所有权并淡入，同时聚焦当前房间。
##
## @return 无返回值。
func show_map() -> void:
	if _motion.is_open_requested():
		return
	var tree := get_tree()
	# 收起尚未完成时重新打开，继续沿用这一轮暂停记录，不能把自己的暂停记成外部暂停。
	if not _owns_open_state:
		_was_paused_before_open = tree.paused
		_owns_open_state = true
	tree.paused = true
	visible = true
	call_deferred("focus_current_room")
	_motion.play_open()


## 开始收起大地图；动画完成后才隐藏并归还本次打开造成的暂停。
##
## @return 无返回值。
func hide_map() -> void:
	if not _owns_open_state or not _motion.is_open_requested():
		return
	_motion.play_close(_finish_map_close)


func _finish_map_close() -> void:
	visible = false
	_restore_pause_if_owned()


## 切换大地图显示状态。
##
## @return 无返回值。
func toggle_map() -> void:
	# 退场期间仍可见，因此快捷键要依据目标状态，才能反向接续当前动画。
	if _motion.is_open_requested():
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
	if not _motion.is_open_requested() or _motion.is_animating():
		return
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
	if not _motion.is_open_requested() or _motion.is_animating():
		return
	if _map_model == null or not map_canvas.has_method(&"canvas_position_to_logical"):
		return
	var logical_position: Vector2 = map_canvas.call(&"canvas_position_to_logical", canvas_position)
	_map_model.call(&"remove_nearest_player_marker", logical_position, marker_delete_radius)


func _on_current_room_changed(_position: Vector2i) -> void:
	if visible:
		focus_current_room()


## 接过最后一个界面关闭时恢复游戏的责任，保留其它暂停界面的展开状态。
## 参数无；仅本地图仍占有暂停时返回 true，否则返回 false。
func take_pause_release_ownership() -> bool:
	if not _owns_open_state:
		return false
	_was_paused_before_open = false
	return true


func _restore_pause_if_owned() -> void:
	if not _owns_open_state:
		return
	_owns_open_state = false
	var tree := get_tree()
	if tree != null and not _was_paused_before_open:
		var settlement: Node = get_node_or_null("/root/SettlementManager")
		if settlement != null and bool(settlement.call("is_run_ending")):
			return
		# 先退出占有状态，再把恢复责任交给仍开着或仍在退场的暂停界面。
		# 否则两个界面的关闭动画交叠时，会提前恢复游戏或永久留下暂停。
		for value: Variant in tree.get_nodes_in_group(PAUSE_OWNERS_GROUP):
			if not is_instance_valid(value) or value == self:
				continue
			var pause_owner: Node = value as Node
			if pause_owner.has_method(PAUSE_HANDOFF_METHOD) and bool(pause_owner.call(PAUSE_HANDOFF_METHOD)):
				return
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
