extends Node

## 建筑输入协调器：连接背包意图、落点预览、房间状态与 F 键交互。
## 规则交给 BuildingService，实体交给 BuildingView，状态交给 RoomBuildingStore。

## 默认地面表现，所有建筑可通过 WorldScene 覆盖。
const DEFAULT_VIEW: PackedScene = preload("res://scenes/building/building_view.tscn")
## 规则服务脚本；实例之间不共享结算锁。
const SERVICE_SCRIPT: GDScript = preload("res://core/building/building_service.gd")
## 表现扩展基类，避免配置一个只有同名方法但不兼容的场景。
const VIEW_SCRIPT: GDScript = preload("res://core/building/building_view.gd")
## 玩家实体路径；与承载数值的 Player 节点分离。
@export var PlayerBodyPath: NodePath = ^"../../PlayerChar"
## 玩家上下文端口路径。
@export var GameplayPortPath: NodePath = ^"../GameplayPort"
## 行动值结算端口；测试和独立玩法可注入各自的时间节点。
@export var TimeSystemPath: NodePath = ^"/root/TimeSystem"
## 世界门禁路径，阻止战斗和过场期间的建造与使用。
@export var WorldCoordinatorPath: NodePath = ^"../WorldInteractionCoordinator"
## 房间视图路径，提供当前地图坐标和房间实例。
@export var MapViewPath: NodePath = ^"../../MapSystem/MapInstantiator"
## 房间世界模型路径，提供房间尺寸。
@export var MapModelPath: NodePath = ^"../../MapSystem/MapWorldModel"
## 本局建筑仓库路径。
@export var StorePath: NodePath = ^"../../RuntimeState/RoomBuildingStore"
## 建筑表现层路径，放在棋盘下以跟随战斗期间的隐藏规则。
@export var BuildingsRootPath: NodePath = ^"../../BoardSystem/BoardController/BuildingsRoot"
## HUD 操作提示路径。
@export var HintPath: NodePath = ^"../../UI/HUDLayer/HUDRoot/BuildingHint"
## 模态界面容器；其可见子界面打开时暂停建筑操作。
@export var OverlayPath: NodePath = ^"../../UI/HUDLayer/HUDRoot/CenterOverlay"
## 地形实体碰撞层；默认第 6 层，与 PlayerChar 的碰撞掩码一致。
@export_flags_2d_physics var ObstacleMask: int = 32
## 玩家脚下预留半径，防止建筑实体把角色卡在占地内。
@export_range(1.0, 100.0) var PlayerClearance: float = 20.0
## 成功或失败提示的可见秒数，运行时可调整。
@export_range(0.1, 10.0) var FeedbackSeconds: float = 2.5

## 规则服务实例。
var _service: RefCounted = SERVICE_SCRIPT.new()
## 当前本局建筑状态仓库。
var _store: Node
## 玩家数值与库存端口。
var _port: Node
## 世界状态协调器。
var _coordinator: Node
## 玩家地面实体。
var _player_body: CharacterBody2D
## 当前房间视图。
var _map_view: Node
## 当前地图模型。
var _map_model: Node
## 建筑实体父节点。
var _buildings_root: Node2D
## HUD 提示标签。
var _hint: Label
## 模态 UI 容器。
var _overlay: Control
## 当前房间的地图坐标。
var _room: Vector2i
## 当前房间节点；卸载时由房间信号替换。
var _room_scene: Node2D
## 正在预览的建筑牌；取消不触碰库存。
var _placing_data: Resource
## 仅用于展示落点的预览节点。
var _preview: Node2D
## 建筑实例 id 到表现节点的映射。
var _views: Dictionary = {}
## 最近一次反馈文本。
var _feedback: String = ""
## 反馈剩余真实秒数。
var _feedback_left: float = 0.0
## 当前正在拆除的实例标识，负数表示没有活动拆除；一次按下仅选定一栋。
var _demolition_id: int = -1


## 解析场景依赖并连接意图；无参数，无返回值。
func _ready() -> void:
	_store = get_node(StorePath)
	_port = get_node(GameplayPortPath)
	_coordinator = get_node(WorldCoordinatorPath)
	_player_body = get_node(PlayerBodyPath) as CharacterBody2D
	_map_view = get_node(MapViewPath)
	_map_model = get_node(MapModelPath)
	_buildings_root = get_node(BuildingsRootPath) as Node2D
	_hint = get_node(HintPath) as Label
	_overlay = get_node(OverlayPath) as Control
	_port.connect("BuildingPlacementRequested", BeginPlacement)
	_map_view.connect("on_entered_room", _on_room_entered)
	_store.connect("BuildingsChanged", _on_buildings_changed)
	get_window().focus_exited.connect(_cancel_demolition)
	# Gameplay 先于 MapSystem 初始化，延后一帧才能读取初始房间。
	call_deferred("_bind_initial_room")


## 进入房间后刷新表现；room 为地图坐标，scene 为房间根节点，无返回值。
func _on_room_entered(room: Vector2i, scene: Node2D) -> void:
	_cancel_demolition()
	CancelPlacement()
	_room = room
	_room_scene = scene
	_rebuild_views()


## 首帧绑定当前房间，避免依赖首次进入信号的节点顺序。
func _bind_initial_room() -> void:
	_on_room_entered(_map_view.get("current_position"), _map_view.get("current_scene") as Node2D)


## 请求进入放置模式；data 为玩家背包建筑牌，无返回值。
func BeginPlacement(data: Resource) -> void:
	_cancel_demolition()
	CancelPlacement()
	if not _world_available() or data == null or not data.has_method("IsBuildingCard"):
		return
	if not bool(data.call("IsBuildingCard")) or not bool(_inventory().call("HasItem", data, 1)):
		return
	_cancel_world_hold()
	_placing_data = data
	_preview = DEFAULT_VIEW.instantiate() as Node2D
	_buildings_root.add_child(_preview)
	_preview.call("Configure", data, true)
	_feedback_left = 0.0


## 取消预览；无参数，无返回值，不消耗库存或行动值。
func CancelPlacement() -> void:
	_placing_data = null
	if is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	if is_instance_valid(_hint):
		_hint.hide()


## 暂停时取消未提交的落点；what 为节点通知编号，无返回值。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		CancelPlacement()
		_cancel_demolition()


## 离开场景时取消本节点拥有的长按，避免残留回调；无参数，无返回值。
func _exit_tree() -> void:
	_cancel_demolition()


## 提前消费建造期间的退出与鼠标输入，避免同时触发暂停或地形采集。
func _input(event: InputEvent) -> void:
	if _placing_data == null:
		_handle_demolition_input(event)
		return
	if event.is_action_pressed("pause_game"):
		CancelPlacement()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not _has_open_overlay():
		# 背包、暂停按钮等 HUD 控件仍先处理自己的点击，不能把 UI 点击当落点。
		if event.button_index == MOUSE_BUTTON_LEFT and get_viewport().gui_get_hovered_control() != null:
			return
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			get_viewport().set_input_as_handled()
			if event.pressed:
				if event.button_index == MOUSE_BUTTON_RIGHT:
					CancelPlacement()
				else:
					_confirm_placement()


## 只在 UI 未消费 F 的首次按下时交互，键盘重复事件不会重复扣费。
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact_building") or event.is_echo():
		return
	if _placing_data != null or not _world_available() or _has_open_overlay():
		return
	# 按下瞬间重新选目标，避免沿用上一帧已离开的建筑。
	var record: Dictionary = _nearest_building()
	if record.is_empty():
		return
	get_viewport().set_input_as_handled()
	_cancel_demolition()
	_cancel_world_hold()
	# 建筑效果与时间只经服务结算一次。
	var result: Dictionary = _service.call("TryInteract", record, _context(), get_node(TimeSystemPath))
	_show_feedback(String(result.get("message", "")))


## 每帧刷新落点与最近建筑提示；delta 为真实帧间隔，无返回值。
func _process(delta: float) -> void:
	_feedback_left = maxf(0.0, _feedback_left - delta)
	if not _world_available() or _has_open_overlay():
		CancelPlacement()
		_cancel_demolition()
		_hint.hide()
		_set_focus(-1)
		return
	_hint.show()
	if _placing_data != null:
		# 鼠标世界坐标来自画布变换，兼容角色相机平移与缩放。
		var point: Vector2 = _buildings_root.get_global_mouse_position()
		# 本次预检的失败原因；空字符串表示可以继续。
		var reason: String = _placement_failure(point)
		_preview.global_position = point
		_preview.call("SetPlacementValid", reason.is_empty())
		_hint.text = "左键放置 %s · 右键 / Esc 取消\n%s" % [
			_placing_data.get("CardName"),
			_feedback if _feedback_left > 0.0 else ("可以放置" if reason.is_empty() else reason)]
		_set_focus(-1)
		return
	if _demolition_id >= 0:
		# 目标、鼠标、世界状态持续有效才允许进度完成；外部取消长按也清理提示。
		var hold: Node = _world_hold()
		if not _can_continue_demolition() or hold == null or not bool(hold.get("is_holding")):
			_cancel_demolition()
		else:
			_set_focus(_demolition_id)
			_hint.text = "正在拆除 · 松开左键或移开鼠标取消"
			return
	# 目标同时决定高亮与文案，防止提示一栋却操作另一栋。
	var record: Dictionary = _nearest_building()
	_set_focus(int(record.get("id", -1)))
	_hint.text = _feedback if _feedback_left > 0.0 else _interaction_prompt(record)
	_hint.visible = not _hint.text.is_empty()


## 同步确认落点，实例化成功后才允许服务消耗建筑牌。
func _confirm_placement() -> void:
	# 待检查的建筑中心位置，交由对应世界或房间坐标接口转换。
	var point: Vector2 = _buildings_root.get_global_mouse_position()
	# 本次预检的失败原因；空字符串表示可以继续。
	var reason: String = _placement_failure(point)
	if not reason.is_empty():
		_show_feedback(reason)
		return
	# 自定义场景先校验协议，损坏的场景不能吞掉库存牌。
	var view: Node2D = _create_view(_placing_data)
	if view == null:
		_show_feedback("建筑场景配置无效")
		return
	view.free()
	# 确认时重查仓库、库存，预览合法不代表提交必然合法。
	var result: Dictionary = _service.call("TryPlace", _placing_data, _room,
		_room_scene.to_local(point), _room_bounds(), _inventory(), _store, _placement_blockers())
	if bool(result.get("success", false)):
		CancelPlacement()
	_show_feedback(String(result.get("message", "")))


## 预检可达性、占地和物理障碍；point 为世界落点，返回失败原因。
func _placement_failure(point: Vector2) -> String:
	if not _world_available() or _placing_data == null:
		return "当前无法建造"
	if not bool(_inventory().call("HasItem", _placing_data, 1)):
		return "背包里已没有这张建筑牌"
	if point.distance_to(_player_body.global_position) > float(_placing_data.get("PlacementRadius")):
		return "离角色太远了"
	# 先执行纯规则检查，再查询引擎的实体障碍。
	var reason: String = _service.call("GetPlacementFailure", _placing_data,
		_room_scene.to_local(point), _room_bounds(), _store.call("GetBuildings", _room), _placement_blockers())
	if not reason.is_empty():
		return reason
	# 预览没有碰撞，不会与它自己的查询结果冲突。
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = _placing_data.get("Footprint")
	# 落点实体查询参数，范围与建筑完整占地保持一致。
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	# 查询包含玩家实际碰撞层，不能只用脚下预留半径替代 100×140 的角色碰撞体。
	query.collision_mask = ObstacleMask | _player_body.collision_layer
	if not _player_body.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		return "这里有角色或障碍物"
	return ""


## 返回玩家脚下与棋盘卡牌的占地矩形，统一转换到房间局部坐标。
func _placement_blockers() -> Array:
	# 角色中心在当前房间内的位置，用于统一占地比较。
	var player_local: Vector2 = _room_scene.to_local(_player_body.global_position)
	# 当前房间内的占地矩形数组，空数组表示没有额外阻挡。
	var blockers: Array = [Rect2(player_local - Vector2.ONE * PlayerClearance,
		Vector2.ONE * PlayerClearance * 2.0)]
	# 卡牌可能没有实体碰撞，另用可见图标边界防止建筑盖住地形交互。
	for card: Node2D in _buildings_root.get_parent().call("GetActiveCardsSnapshot"):
		# 卡牌图标节点，用它的可见矩形校验建筑不能盖住已有卡牌。
		var icon: Sprite2D = card.get_node_or_null("Icon") as Sprite2D
		if icon == null or icon.texture == null or not icon.is_visible_in_tree():
			continue
		# 角点先转到世界再转回房间，不能直接混用棋盘和房间坐标。
		var rect: Rect2 = icon.get_rect()
		# 图标左上角在当前房间内的位置。
		var start: Vector2 = _room_scene.to_local(icon.to_global(rect.position))
		# 图标右下角在当前房间内的位置。
		var end: Vector2 = _room_scene.to_local(icon.to_global(rect.end))
		blockers.append(Rect2(start, end - start).abs())
	return blockers


## 返回当前房间可建地面矩形，尺寸从地图模型读取。
func _room_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, _map_model.get("room_size"))


## 选择当前房间、半径内且没有墙体遮挡的最近建筑；返回空字典表示无目标。
func _nearest_building() -> Dictionary:
	# 当前最近的有效建筑记录；空字典表示没有可交互目标。
	var nearest: Dictionary = {}
	# 已选目标距离，初始无穷大使第一个有效目标可以参与比较。
	var distance: float = INF
	for record: Dictionary in _store.call("GetBuildings", _room):
		# 待检查的建筑中心位置，交由对应世界或房间坐标接口转换。
		var point: Vector2 = _room_scene.to_global(record["position"])
		# 角色与候选建筑中心的实际世界距离。
		var candidate_distance: float = _player_body.global_position.distance_to(point)
		if candidate_distance >= distance or not _is_record_reachable(record):
			continue
		nearest = record
		distance = candidate_distance
	return nearest


## 检查距离与遮挡；record 为当前仓库记录，返回是否允许使用或拆除。
func _is_record_reachable(record: Dictionary) -> bool:
	# 交互与拆除共享同一距离门禁，不允许隔墙远程破坏。
	var point: Vector2 = _room_scene.to_global(record["position"])
	if _player_body.global_position.distance_to(point) > float(record["data"].get("InteractionRadius")):
		return false
	# 排除目标自身碰撞，但其它建筑与墙体仍阻挡射线。
	var view: Node2D = _views.get(int(record["id"])) as Node2D
	if not is_instance_valid(view) or not view.is_visible_in_tree():
		return false
	# 射线沿角色中心到目标中心查询实体阻挡。
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		_player_body.global_position, point, ObstacleMask, [_player_body.get_rid()])
	# 目标实体需要排除，避免将建筑自身误认为隔墙。
	var body: CollisionObject2D = view.get_node_or_null("Body") as CollisionObject2D
	if body != null:
		ray.exclude = [_player_body.get_rid(), body.get_rid()]
	return _player_body.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


## 处理拆除左键和全局取消；event 为输入事件，无返回值。
func _handle_demolition_input(event: InputEvent) -> void:
	if _demolition_id >= 0 and event.is_action_pressed("pause_game"):
		_cancel_demolition()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	# 使用 _input 监听松开，即使鼠标移到 UI 上也必须立即取消。
	if _demolition_id >= 0 and ((event.button_index == MOUSE_BUTTON_LEFT and not event.pressed) \
		or (event.button_index == MOUSE_BUTTON_RIGHT and event.pressed)):
		_cancel_demolition()
		get_viewport().set_input_as_handled()
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	if not _world_available() or _has_open_overlay() or get_viewport().gui_get_hovered_control() != null:
		return
	# 只破坏鼠标指向的建筑，不能套用 F 的最近目标选择。
	var record: Dictionary = _building_under_pointer()
	if record.is_empty():
		return
	get_viewport().set_input_as_handled()
	_begin_demolition(record)


## 返回鼠标覆盖的建筑记录；无目标时返回空字典。
func _building_under_pointer() -> Dictionary:
	# 鼠标坐标先统一到世界空间，再转换到每个建筑局部空间。
	var point: Vector2 = _mouse_world_position()
	for record: Dictionary in _store.call("GetBuildings", _room):
		# 使用配置占地而非纹理分辨率，保持各类自定义建筑点击范围一致。
		var view: Node2D = _views.get(int(record["id"])) as Node2D
		# 命中范围使用完整占地，透明图标边缘仍属于建筑。
		var footprint: Vector2 = record["data"].get("Footprint")
		if is_instance_valid(view) and view.is_visible_in_tree() \
			and Rect2(-footprint / 2.0, footprint).has_point(view.to_local(point)):
			return record
	return {}


## 开始一次拆除；record 为鼠标命中记录，无返回值，不提前移除建筑。
func _begin_demolition(record: Dictionary) -> void:
	_cancel_demolition()
	if not _world_available() or _has_open_overlay() or _placing_data != null:
		return
	if not _is_record_reachable(record):
		_show_feedback("请靠近建筑，并确保中间没有障碍")
		return
	# 只读建筑配置决定能否拆除和长按秒数。
	var data: Resource = record["data"]
	if not data.has_method("CanDemolish") or not bool(data.call("CanDemolish")):
		_show_feedback("这座建筑不能拆除")
		return
	# 生成掉落必须有有效棋盘，不能先删建筑再发现掉落端口缺失。
	var board: Node = _buildings_root.get_parent()
	# 所有世界长按共用同一计时端口，防止同时完成多个交互。
	var hold: Node = _world_hold()
	if hold == null or not hold.has_method("begin_timed_hold") or not board.has_method("SpawnLootCards"):
		_show_feedback("暂时无法拆除")
		return
	_cancel_world_hold()
	_demolition_id = int(record["id"])
	_feedback_left = 0.0
	# 圆环锚定可见图标，随相机移动保持贴合目标。
	var view: Node2D = _views[_demolition_id]
	hold.call("begin_timed_hold", self, float(data.get("DemolitionHoldSeconds")),
		Callable(self, "_complete_demolition"), view.get_node("Icon"))


## 检查完成瞬间的输入及目标状态，避免 Tween 比下一帧门禁先结算。
func _can_continue_demolition() -> bool:
	if _demolition_id < 0 or not _is_demolition_button_pressed() or not _world_available() \
		or _placing_data != null or _has_open_overlay() or get_viewport().gui_get_hovered_control() != null:
		return false
	# 重新命中当前鼠标目标，不能沿用开始长按时的旧引用。
	var record: Dictionary = _building_under_pointer()
	return not record.is_empty() and int(record["id"]) == _demolition_id and _is_record_reachable(record)


## 长按完成后再次校验，先移除实例，再经现有棋盘掉落链生成物品卡。
func _complete_demolition() -> void:
	if not _can_continue_demolition():
		_cancel_demolition()
		return
	# 取消长按会清理控制器标识，因此先固定待提交的实例。
	var instance_id: int = _demolition_id
	# 掉落使用棋盘公开接口，和地形掉落共用拾取流程。
	var board: Node = _buildings_root.get_parent()
	_cancel_demolition()
	if not is_instance_valid(board) or not board.has_method("SpawnLootCards"):
		return
	# 只有首次成功移除才返回可发放的掉落数组。
	var result: Dictionary = _service.call("TryDemolish", _room, instance_id, _store)
	if bool(result.get("success", false)):
		board.call("SpawnLootCards", result["drops"], _room_scene.to_global(result["position"]))
	_show_feedback(String(result.get("message", "")))


## 仅取消本建筑控制器持有的长按，不干扰随后接管圆环的其它交互。
func _cancel_demolition() -> void:
	_demolition_id = -1
	# 按拥有者取消，避免中断已经由其它世界交互接管的圆环。
	var hold: Node = _world_hold()
	if hold != null:
		hold.call("cancel_hold_for", self)


## 读取世界鼠标坐标；独立输入接口便于回归场景注入确定的位置。
func _mouse_world_position() -> Vector2:
	return _buildings_root.get_global_mouse_position()


## 读取当前左键是否仍按住，避免失焦或丢失释放事件导致误拆。
func _is_demolition_button_pressed() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


## 当前房间有增删时刷新，其他房间保持纯数据状态。
func _on_buildings_changed(room: Vector2i) -> void:
	if room == _room:
		_rebuild_views()


## 从仓库重建当前房间建筑；节点释放不影响实例状态。
func _rebuild_views() -> void:
	_cancel_demolition()
	for view: Node2D in _views.values():
		_buildings_root.remove_child(view)
		view.queue_free()
	_views.clear()
	if not is_instance_valid(_room_scene):
		return
	for record: Dictionary in _store.call("GetBuildings", _room):
		# 该建筑的独立表现节点，生命周期不影响仓库状态。
		var view: Node2D = _create_view(record["data"])
		if view == null:
			continue
		_buildings_root.add_child(view)
		view.global_position = _room_scene.to_global(record["position"])
		view.call("Configure", record["data"], false)
		_views[int(record["id"])] = view


## 创建并校验可扩展表现；data 为配置，返回未挂树的节点或 null。
func _create_view(data: Resource) -> Node2D:
	# 建筑的可选专属场景；空值使用统一默认表现。
	var scene: PackedScene = data.get("WorldScene") as PackedScene
	# 尚未加入场景树的表现实例，先校验协议再消耗库存。
	var instance: Node = (DEFAULT_VIEW if scene == null else scene).instantiate()
	if instance is VIEW_SCRIPT and instance.get_node_or_null("Icon") is Sprite2D \
		and instance.get_node_or_null("Body") is StaticBody2D \
		and instance.get_node_or_null("Body/CollisionShape2D") is CollisionShape2D:
		return instance as Node2D
	instance.free()
	return null


## 通过公开门禁检查世界状态与角色生存状态。
func _world_available() -> bool:
	if not is_instance_valid(_room_scene) or not is_instance_valid(_player_body):
		return false
	if not is_instance_valid(_port) or not is_instance_valid(_coordinator):
		return false
	# 依赖尚未初始化或已被释放时关闭交互，不能对空的生命组件调用方法。
	var health: Node = _port.get("PlayerHealth") as Node
	return is_instance_valid(health) and int(health.get("CurrentValue")) > 0 \
		and bool(_coordinator.call("CanUseWorld"))


## 检查背包、制作或仓库是否占用输入。
func _has_open_overlay() -> bool:
	for child: Node in _overlay.get_children():
		if child is Control and child.is_visible_in_tree():
			return true
	return false


## 读取玩家库存，避免建筑系统直接访问 Player 的私有成员。
func _inventory() -> Node:
	return _port.get("PlayerInventory") as Node


## 构建交互策略上下文，供后续制作台等策略使用。
func _context() -> Dictionary:
	return {"health": _port.get("PlayerHealth"), "inventory": _inventory(),
		"player": _port.get("Player"), "gameplay_port": _port}


## 生成靠近提示，同时显示不可用原因。
func _interaction_prompt(record: Dictionary) -> String:
	if record.is_empty():
		return ""
	# 当前建筑配置的策略资源，不通过建筑标识硬编码效果。
	var interaction: Resource = record["data"].get("Interaction")
	# 本次预检的失败原因；空字符串表示可以继续。
	var reason: String = interaction.call("get_unavailable_reason", _context(), record["state"])
	# 不可拆建筑不展示拆除入口，避免 HUD 提示无效操作。
	var demolition_prompt: String = ""
	if bool(record["data"].call("CanDemolish")):
		demolition_prompt = "\n长按左键 %.1f 秒拆除" % float(record["data"].get("DemolitionHoldSeconds"))
	return "[F] %s · %s%s%s" % [record["data"].get("CardName"), interaction.call("get_prompt"),
		"" if reason.is_empty() else "\n" + reason, demolition_prompt]


## 将目标高亮限制在唯一最近实例上。
func _set_focus(instance_id: int) -> void:
	for id: int in _views:
		_views[id].call("SetFocused", id == instance_id)


## 新建筑操作取消旧的鼠标长按，避免两种交互同时结算。
func _cancel_world_hold() -> void:
	# 既有世界长按控制器，新建筑操作开始前需取消它的待完成请求。
	var hold: Node = _world_hold()
	if hold != null:
		hold.call("cancel_active_hold")


## 解析共享长按端口；初始化或销毁阶段依赖不存在时返回 null。
func _world_hold() -> Node:
	if not is_instance_valid(_coordinator):
		return null
	return _coordinator.get_node_or_null("WorldHoldInteractionController")


## 设置短暂反馈，随后自动恢复靠近提示。
func _show_feedback(message: String) -> void:
	_feedback = message
	_feedback_left = FeedbackSeconds
