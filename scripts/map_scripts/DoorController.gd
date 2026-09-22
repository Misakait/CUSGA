extends Node2D
## 四方向偏移：[上, 右, 下, 左]；与 map_button.gd / map_position_create.gd 逐项一致。
const DIR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(1, 0),
	Vector2i(0, -1),
]

## 反向映射：方向索引 → 对侧方向索引；与 map_position_create.gd 的 OPPOSITE_DIR 逐项一致，
## 用于把「去哪个方向」翻译成「从对面那扇门出生」。
const OPPOSITE_DIR: Array[int] = [2, 3, 0, 1]

## 门节点名，顺序必须与 DIR_OFFSETS 一一对应。
const DOOR_NODE_NAMES: Array[StringName] = [
	&"UpDoor",
	&"RightDoor",
	&"DownDoor",
	&"LeftDoor",
]

## 一条连接也没有的房间，其连接数组的缺省形状；与 map_button.gd 的取值方式保持一致。
const NO_CONNECTION: Array = [0, 0, 0, 0]

## 目标场景字段为空串时表示该方向没有连通房间。不能用「坐标等于原点」来判断，
## 因为 (0, 0) 是合法房间坐标。
const NO_TARGET: String = ""

## 地图系统挂载路径；地图房间由 MapInstantiator 加载。用路径常量而不是 @onready，
## 是为了兼容 SceneManager 在「初始场景尚未 ready」阶段就调用 init() 的既有约定。
const MAP_INSTANTIATOR_PATH: NodePath = ^"../MapInstantiator"

## 小地图挂载路径；随房间移动刷新已走过的格子。
const MAP_LITTLE_PATH: NodePath = ^"../MapLittle"

## 地图按钮挂载路径。地图移动改为门碰撞驱动后，方向按钮在运行时隐藏（节点保留，逻辑不动）。
const MAP_BUTTON_PATH: NodePath = ^"../MapButton"

## 场景过渡 Autoload 的固定挂载路径。
const SCREEN_TRANSITIONS_PATH: NodePath = ^"/root/ScreenTransitions"

## 时间 Autoload 的固定挂载路径。
const TIME_SYSTEM_PATH: NodePath = ^"/root/TimeSystem"

## 地图系统进入房间信号名，与 map_control.gd / map_instantiator.gd 的声明逐字一致。
const ON_ENTERED_ROOM_SIGNAL: StringName = &"on_entered_room"

## 门节点实例缓存；键为节点名（StringName），值为门节点。
var doors: Dictionary = {}

var _door_targets: Dictionary = {}

## 由 map_control.gd 注入的表现层玩家角色。
var player: CharacterBody2D

## 当前所在房间的地图坐标；切房后由 _apply_room_targets 更新。
var current_position: Vector2i = Vector2i.ZERO

## 换房流程互斥锁。立即传送模式下，玩家在过场期间仍可能停留在门的范围内，
## 该锁防止过渡尚未结束时重复发起换房。
var _is_room_change_in_progress: bool = false

## 地图系统节点（MapInstantiator）。
var _map_instantiator: Node = null

## 小地图节点（MapLittle）。
var _map_little: Node = null

## 房间切换用的淡入淡出 Autoload。
var _screen_transitions: Node = null

## 行动值消耗用的时间 Autoload；按方法协议调用，与 map_button.gd 一致。
var _time_system: Node = null


func _ready() -> void:
	_cache_doors()
	_bind_map_system()
	_apply_room_targets(_read_current_room_position())
	_apply_spawn_placement()

func _read_current_room_position() -> Vector2i:
	if _map_instantiator == null:
		return Vector2i.ZERO

	var raw: Variant = _map_instantiator.get(&"current_position")
	if typeof(raw) == TYPE_VECTOR2I:
		return raw

	return Vector2i.ZERO

func GetDoorTargetSummary() -> Array[String]:
	var summary: Array[String] = []
	for name in DOOR_NODE_NAMES:
		var door: Node = _door_by_name(name)
		if door == null:
			summary.append("%s=<缺失>" % name)
			continue

		summary.append(
			"%s=%s->%s" % [name, str(door.get(&"target_scene_id")), str(door.get(&"target_door_id"))]
		)

	return summary

func OnDoorBodyEntered(door: Node, body: Node2D) -> void:
	if door == null or not is_instance_valid(door):
		return

	if body == null or not is_instance_valid(body):
		return

	if not body.is_in_group(&"Player"):
		return

	var target_raw: Variant = _door_targets.get(door.name, null)
	if typeof(target_raw) != TYPE_VECTOR2I:
		# 控制器还没写过目标时，退回读取门自身的静态配置（手工预设的场景）。
		target_raw = _read_door_target_position(door)

	if typeof(target_raw) != TYPE_VECTOR2I:
		# 该方向没有连通房间，门的碰撞已被关闭；这里再兜一层，避免静态配置误触发换房。
		return

	_request_room_change(door, Vector2i(target_raw), str(door.get(&"target_door_id")))

func _format_room_position(value: Vector2i) -> String:
	return "Vector2i(%d, %d)" % [value.x, value.y]

func _read_door_target_position(door: Node) -> Variant:
	var raw: Variant = door.get(&"target_scene_id")
	if typeof(raw) == TYPE_VECTOR2I:
		return raw

	if not (raw is String):
		return null

	var text: String = (raw as String).strip_edges()
	if text.is_empty():
		return null

	# 同时兼容 "Vector2i(8, 8)" 与旧式 "(8, 8)" 两种写法。
	var normalized: String = text
	if normalized.begins_with("("):
		normalized = "Vector2i" + normalized

	var parsed: Variant = str_to_var(normalized)
	if typeof(parsed) != TYPE_VECTOR2I:
		push_warning("门 %s 的目标坐标无法解析：'%s'" % [door.name, text])
		return null

	return Vector2i(parsed)

func _cache_doors() -> void:
	doors.clear()
	for door in get_children():
		# 不用 to_lower：门节点名含大写，且 map_control.tscn 里就是按原名实例化的。
		doors[door.name] = door
		# 门不反向查找父节点，由控制器主动注入，避免依赖场景层级。
		door.set(&"controller", self)

	if doors.is_empty():
		push_warning("DoorController 下没有门节点，地图传送将不可用。")
		return

	for name in DOOR_NODE_NAMES:
		if not doors.has(name):
			push_warning("DoorController 缺少 %s，该方向无法传送。" % name)

func _bind_map_system() -> void:
	_map_instantiator = get_node_or_null(MAP_INSTANTIATOR_PATH)
	_map_little = get_node_or_null(MAP_LITTLE_PATH)
	_screen_transitions = get_node_or_null(SCREEN_TRANSITIONS_PATH)
	_time_system = get_node_or_null(TIME_SYSTEM_PATH)

	var map_button: Node = get_node_or_null(MAP_BUTTON_PATH)
	if map_button is CanvasItem:
		# 地图移动改由门碰撞驱动；按钮节点保留（脚本与信号连接不动），仅在运行时不可见。
		(map_button as CanvasItem).visible = false

	if _map_instantiator == null:
		push_error("DoorController 未找到 MapInstantiator（%s），门无法切换房间。" % MAP_INSTANTIATOR_PATH)
		return

	if not _map_instantiator.has_signal(ON_ENTERED_ROOM_SIGNAL):
		push_error("MapInstantiator 缺少 %s 信号，门的目标不会随房间更新。" % ON_ENTERED_ROOM_SIGNAL)
		return

	var room_callable: Callable = Callable(self, "_on_map_entered_room")
	if not _map_instantiator.is_connected(ON_ENTERED_ROOM_SIGNAL, room_callable):
		_map_instantiator.connect(ON_ENTERED_ROOM_SIGNAL, room_callable)

func _on_map_entered_room(position: Vector2i, _scene: Node2D) -> void:
	_apply_room_targets(position)
	_update_little_map(position)
	_is_room_change_in_progress = false

func _apply_room_targets(position: Vector2i) -> void:
	current_position = position

	if _map_instantiator == null:
		return

	var connections: Variant = _map_instantiator.map_position.scene_to_scene.get(position, NO_CONNECTION)
	var connection_row: Array = connections as Array

	for direction in DOOR_NODE_NAMES.size():
		var door_name: StringName = DOOR_NODE_NAMES[direction]
		var door: Node = _door_by_name(door_name)
		if door == null:
			continue

		var connected: bool = (
			direction < connection_row.size() and int(connection_row[direction]) == 1
		)
		if connected:
			_door_targets[door_name] = position + DIR_OFFSETS[direction]
			_configure_door(
				door,
				_format_room_position(_door_targets[door_name]),
				str(DOOR_NODE_NAMES[OPPOSITE_DIR[direction]]),
				true
			)
		else:
			# 清掉权威目标，并关闭碰撞，确保地图边缘的门走到也不会误触发换房。
			_door_targets.erase(door_name)
			_configure_door(door, NO_TARGET, NO_TARGET, false)

func _configure_door(
	door: Node,
	target_scene_id: String,
	target_door_id: String,
	enabled: bool
) -> void:
	door.set(&"target_scene_id", target_scene_id)
	door.set(&"target_door_id", target_door_id)

	if door is CollisionObject2D:
		# 物理回调期间不能同步改 monitoring，必须用 set_deferred 排到帧末。
		(door as CollisionObject2D).set_deferred(&"monitoring", enabled)

func _request_room_change(
	door: Node,
	target_position: Vector2i,
	target_spawn_door_id: String
) -> void:
	if _is_room_change_in_progress:
		return

	if _map_instantiator == null:
		push_error("DoorController 未绑定 MapInstantiator，无法切换房间。")
		return

	_is_room_change_in_progress = true

	if not _move_little_map_position(target_position):
		_is_room_change_in_progress = false
		return

	if _screen_transitions == null or not _screen_transitions.has_method(&"fade_out"):
		push_error("DoorController 未找到 ScreenTransitions，无法播放过场。")
		_is_room_change_in_progress = false
		return

	_screen_transitions.fade_out()
	await _screen_transitions.fade_complete

	if _time_system != null and _time_system.has_method(&"PassMapMoveTime"):
		_time_system.call(&"PassMapMoveTime")
	else:
		push_warning("DoorController 未找到 TimeSystem，本次移动不消耗行动值。")

	# 出发门立即进入冷却，这是防「反复横跳」的关键：Door.gd 的冷却只在 _ready 初始化一次，
	# 不主动重置就只能拦住门创建后的头 1 秒，挡不住玩家在传送点上反复触发。
	_reset_door_cool_down(door)

	var spawn_door: Node = _door_by_name(target_spawn_door_id)
	if spawn_door != null:
		_place_player_at_door(spawn_door)

	_map_instantiator.load_scene_at(target_position)


## 让出发门重新开始冷却计时，避免玩家在传送点上连续触发。
func _reset_door_cool_down(door: Node) -> void:
	if door == null or not is_instance_valid(door):
		return

	if door.has_method(&"reset_cool_down"):
		door.call(&"reset_cool_down")
	else:
		push_warning("门 %s 缺少 reset_cool_down，本次传送后不会进入冷却。" % door.name)


func _place_player_at_door(door: Node) -> void:
	if player == null or not is_instance_valid(player):
		push_warning("DoorController 未绑定玩家角色，本次落位跳过。")
		return

	if not (door is Node2D):
		return

	# Door.gd 在 _ready 里把第 2 个子节点（Offeset）的位置存进 offset，缺失时为零向量。
	var offset: Variant = door.get(&"offset")
	if typeof(offset) != TYPE_VECTOR2:
		offset = Vector2.ZERO

	player.global_position = (door as Node2D).global_position + (offset as Vector2)

func _apply_spawn_placement() -> void:
	if SceneManager.target_spawn_id.is_empty():
		return

	var spawn_door: Node = _door_by_name(SceneManager.target_spawn_id)
	# 无论是否命中都清空，避免该标记残留到下一次不相关的房间加载。
	SceneManager.target_spawn_id = ""

	if spawn_door == null:
		return

	_place_player_at_door(spawn_door)

func _move_little_map_position(target_position: Vector2i) -> bool:
	if _map_little == null or not _map_little.has_method(&"build_little_map"):
		push_warning("DoorController 未能使用 MapLittle，本次移动跳过小地图刷新。")
		return true

	var previous_position: Vector2i = current_position
	_map_little.call(&"build_little_map", target_position.x, target_position.y)
	_map_little.call(&"change_this_cell_color", target_position.x, target_position.y)

	# 只在坐标真的变了才擦旧格：首次进入房间时两者相同，擦除会把当前位置的颜色抹掉。
	if previous_position != target_position and _map_little.has_method(&"return_this_cell_color"):
		_map_little.call(&"return_this_cell_color", previous_position.x, previous_position.y)

	return true

func _update_little_map(position: Vector2i) -> void:
	if _map_little == null or not _map_little.has_method(&"change_this_cell_color"):
		return

	_map_little.call(&"change_this_cell_color", position.x, position.y)

func _door_by_name(door_name: StringName) -> Node:
	return doors.get(door_name, null)
