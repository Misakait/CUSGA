extends Node

## 建筑输入协调器：连接背包意图、落点预览、房间状态与 F 键交互。
## 规则交给 BuildingService，实体交给 BuildingView，状态交给 RoomBuildingStore。

## 默认地面表现，所有建筑可通过 WorldScene 覆盖。
const DEFAULT_VIEW: PackedScene = preload("res://scenes/building/building_view.tscn")
## 规则服务脚本；实例之间不共享结算锁。
const SERVICE_SCRIPT: GDScript = preload("res://core/building/building_service.gd")
## 表现扩展基类，避免配置一个只有同名方法但不兼容的场景。
const VIEW_SCRIPT: GDScript = preload("res://core/building/building_view.gd")
## 飘字服务 Autoload 的固定挂载路径。
## 必须走 NodePath 而不是直接写 FloatingText 标识符：test_run 环境没有 autoload，
## 裸标识符会让整个脚本以「Identifier not found」解析失败，而不是运行时报错。
const FLOATING_TEXT_PATH: NodePath = ^"/root/FloatingText"
## 飘字服务的两个公开入口方法名；动态协议名集中定义，避免字符串散落到调用点。
const FLOATING_TEXT_SHOW_AT_TARGET: StringName = &"show_at_target"
const FLOATING_TEXT_SHOW_AT_WORLD: StringName = &"show_at_world"
## 距离不足时显示的文案；与棋盘卡共用同一措辞，让「距离不够」在全工程只有一种说法。
const OUT_OF_RANGE_TEXT: String = "距离不够！"
## 建筑成功提示的颜色。
## 刻意在本文件定义而不从飘字服务读取：飘字服务是可选依赖（缺失时必须静默降级），
## 调用方一旦 preload 服务脚本就会重新引入编译期耦合，从而失去这个降级能力。
const SUCCESS_TEXT_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
## 建筑失败提示的颜色；与飘字服务的默认红保持同一语义。
const FAILURE_TEXT_COLOR: Color = Color(1.0, 0.25, 0.2, 1.0)
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
## 活动房间各自持有建筑视图索引；交互仍只读取当前房间的 _views。
var _views_by_room: Dictionary = {}
## 当前正在拆除的实例标识，负数表示没有活动拆除；一次按下仅选定一栋。
var _demolition_id: int = -1
## 飘字服务 Autoload；缺失时静默降级为「不显示提示」，不影响任何交互判定。
var _floating_text: Node = null


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
	_map_view.connect("room_activated", _on_room_activated)
	_map_view.connect("room_deactivating", _on_room_deactivating)
	_store.connect("BuildingsChanged", _on_buildings_changed)
	get_window().focus_exited.connect(_cancel_demolition)
	_floating_text = get_node_or_null(FLOATING_TEXT_PATH)
	if _floating_text == null:
		# 可降级依赖：没有飘字服务时全部交互判定照常生效，只是玩家看不到提示。
		push_warning("BuildingController 未找到 FloatingText Autoload，建筑提示将不会显示：%s" % FLOATING_TEXT_PATH)
	# Gameplay 先于 MapSystem 初始化，延后一帧才能读取初始房间。
	call_deferred("_bind_initial_room")


## 进入房间后刷新表现；room 为地图坐标，scene 为房间根节点，无返回值。
func _on_room_entered(room: Vector2i, scene: Node2D) -> void:
	_cancel_demolition()
	CancelPlacement()
	_room = room
	_room_scene = scene
	if not _views_by_room.has(room):
		_rebuild_room_views(room)
	_views = _views_by_room.get(room, {})


## 首帧绑定当前房间，避免依赖首次进入信号的节点顺序。
func _bind_initial_room() -> void:
	for room_value: Variant in (_map_view.get("active_instances") as Dictionary).keys():
		var room: Vector2i = room_value
		if not _views_by_room.has(room):
			_rebuild_room_views(room)
	_on_room_entered(_map_view.get("current_position"), _map_view.get("current_scene") as Node2D)


## 新房间就绪后立即建立建筑视图，邻房也可实时运行。
## @param room 房间坐标。
## @param _scene 房间场景。
## @return 无返回值。
func _on_room_activated(room: Vector2i, _scene: Node2D) -> void:
	_rebuild_room_views(room)


## 释放窗口外建筑视图与索引，不动建筑仓库。
## @param room 房间坐标。
## @param _scene 即将释放的房间场景。
## @return 无返回值。
func _on_room_deactivating(room: Vector2i, _scene: Node2D) -> void:
	if room == _room:
		_cancel_demolition()
	_views_by_room.erase(room)
	if room == _room:
		_views = {}


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
	if _map_view != null and is_instance_valid(_map_view):
		for pair: Array in [["room_activated", _on_room_activated], ["room_deactivating", _on_room_deactivating]]:
			if _map_view.is_connected(pair[0], pair[1]):
				_map_view.disconnect(pair[0], pair[1])


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
	_show_building_result(int(record["id"]), result)


## 每帧刷新落点与最近建筑提示；_delta 为真实帧间隔，无返回值。
##
## 这里只维护「持续状态」：落点预览说明、拆除进行中、F 交互提示。
## 离散的成功/失败结果改由飘字服务播报，因此不再需要反馈倒计时。
func _process(_delta: float) -> void:
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
			"可以放置" if reason.is_empty() else reason]
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
	_hint.text = _interaction_prompt(record)
	_hint.visible = not _hint.text.is_empty()


## 同步确认落点，实例化成功后才允许服务消耗建筑牌。
func _confirm_placement() -> void:
	# 待检查的建筑中心位置，交由对应世界或房间坐标接口转换。
	var point: Vector2 = _buildings_root.get_global_mouse_position()
	# 本次预检的失败原因；空字符串表示可以继续。
	var reason: String = _placement_failure(point)
	if not reason.is_empty():
		# 飘字只挂真实左键提交入口：_placement_failure 每帧被 _process 调用做落点预览，
		# 在那里提示会每秒刷出几十条飘字。
		_show_world_floating_text(point, reason, FAILURE_TEXT_COLOR)
		return
	# 自定义场景先校验协议，损坏的场景不能吞掉库存牌。
	var view: Node2D = _create_view(_placing_data)
	if view == null:
		_show_world_floating_text(point, "建筑场景配置无效", FAILURE_TEXT_COLOR)
		return
	view.free()
	# 确认时重查仓库、库存，预览合法不代表提交必然合法。
	var result: Dictionary = _service.call("TryPlace", _placing_data, _room,
		_room_scene.to_local(point), _room_bounds(), _inventory(), _store, _placement_blockers())
	if bool(result.get("success", false)):
		CancelPlacement()
	_show_world_result(point, result)


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


## 检查建筑是否在交互距离内。
##
## 与遮挡判定分离，使「距离不够」提示能只按距离原因触发；距离口径与原内联判定逐字相同。
##
## @param record 建筑仓库记录。
## @return 玩家与建筑中心的世界距离不超过 InteractionRadius 时为 true。
func _is_record_in_range(record: Dictionary) -> bool:
	# 交互与拆除共享同一距离门禁，不允许隔墙远程破坏。
	var point: Vector2 = _room_scene.to_global(record["position"])
	return _player_body.global_position.distance_to(point) <= float(record["data"].get("InteractionRadius"))


## 检查距离与遮挡；record 为当前仓库记录，返回是否允许使用或拆除。
func _is_record_reachable(record: Dictionary) -> bool:
	if not _is_record_in_range(record):
		return false
	# 射线需要目标中心的世界坐标，因此这里独立求一次，不复用距离入口的局部变量。
	var point: Vector2 = _room_scene.to_global(record["position"])
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
		# 距离不足统一用与棋盘卡相同的文案；纯遮挡只讲障碍，
		# 避免距离其实充足时旧合并文案还叫玩家「靠近建筑」。
		if _is_record_in_range(record):
			_show_building_failure(int(record["id"]), "中间有障碍，无法拆除")
		else:
			_show_building_failure(int(record["id"]), OUT_OF_RANGE_TEXT)
		return
	# 只读建筑配置决定能否拆除和长按秒数。
	var data: Resource = record["data"]
	if not data.has_method("CanDemolish") or not bool(data.call("CanDemolish")):
		_show_building_failure(int(record["id"]), "这座建筑不能拆除")
		return
	# 生成掉落必须有有效棋盘，不能先删建筑再发现掉落端口缺失。
	var board: Node = _buildings_root.get_parent()
	# 所有世界长按共用同一计时端口，防止同时完成多个交互。
	var hold: Node = _world_hold()
	if hold == null or not hold.has_method("begin_timed_hold") or not board.has_method("SpawnLootCards"):
		_show_building_failure(int(record["id"]), "暂时无法拆除")
		return
	_cancel_world_hold()
	_demolition_id = int(record["id"])
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
	# 飘字锚点必须在提交前固定：拆除成功会同步重建 _views 并释放旧视图，
	# 事后既取不到该建筑节点，也拿不到它的世界坐标。
	var anchor_position: Vector2 = _building_world_position(instance_id)
	# 掉落使用棋盘公开接口，和地形掉落共用拾取流程。
	var board: Node = _buildings_root.get_parent()
	_cancel_demolition()
	if not is_instance_valid(board) or not board.has_method("SpawnLootCards"):
		return
	# 只有首次成功移除才返回可发放的掉落数组。
	var result: Dictionary = _service.call("TryDemolish", _room, instance_id, _store)
	if bool(result.get("success", false)):
		board.call("SpawnLootCards", result["drops"], _room_scene.to_global(result["position"]))
	_show_world_floating_text(anchor_position, String(result.get("message", "")), _result_text_color(result))


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
	if (_map_view.get("active_instances") as Dictionary).has(room):
		_rebuild_room_views(room)


## 从仓库重建当前房间建筑；节点释放不影响实例状态。
func _rebuild_views() -> void:
	_rebuild_room_views(_room)


## 只重建指定活动房间，保留其它八房的实体与状态。
## @param room 房间坐标。
## @return 无返回值。
func _rebuild_room_views(room: Vector2i) -> void:
	if room == _room:
		_cancel_demolition()
	var old_views: Dictionary = _views_by_room.get(room, {})
	for view: Node2D in old_views.values():
		if is_instance_valid(view):
			view.queue_free()
	_views_by_room.erase(room)
	var room_scene: Node2D = (_map_view.get("active_instances") as Dictionary).get(room) as Node2D
	if room_scene == null or not is_instance_valid(room_scene):
		return
	var root: Node2D = room_scene.get_node_or_null("RoomContentRoot") as Node2D
	if root == null:
		return
	var room_views: Dictionary = {}
	for record: Dictionary in _store.call("GetBuildings", room):
		# 该建筑的独立表现节点，生命周期不影响仓库状态。
		var view: Node2D = _create_view(record["data"])
		if view == null:
			continue
		root.add_child(view)
		view.position = record["position"]
		view.call("Configure", record["data"], false)
		room_views[int(record["id"])] = view
	_views_by_room[room] = room_views
	if room == _room:
		_views = room_views


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


## 在世界坐标处显示飘字；服务不可用或文案为空时静默跳过。
##
## @param world_position 世界坐标锚点。
## @param message 显示文案。
## @param text_color 正文颜色。
## @return 无返回值。
func _show_world_floating_text(world_position: Vector2, message: String, text_color: Color) -> void:
	if message.is_empty() or not _has_floating_text():
		return
	_floating_text.call(FLOATING_TEXT_SHOW_AT_WORLD, world_position, message, text_color)


## 在建筑处显示飘字。
##
## @param instance_id 建筑实例标识。
## @param message 显示文案。
## @param text_color 正文颜色。
## @return 无返回值。
func _show_building_floating_text(instance_id: int, message: String, text_color: Color) -> void:
	_show_world_floating_text(_building_world_position(instance_id), message, text_color)


## 在世界落点处按服务结果分色显示提示。
##
## @param world_position 世界落点。
## @param result 服务返回的 success/message 字典。
## @return 无返回值。
func _show_world_result(world_position: Vector2, result: Dictionary) -> void:
	_show_world_floating_text(world_position, String(result.get("message", "")), _result_text_color(result))


## 在建筑处按服务结果分色显示提示。
##
## @param instance_id 建筑实例标识。
## @param result 服务返回的 success/message 字典。
## @return 无返回值。
func _show_building_result(instance_id: int, result: Dictionary) -> void:
	_show_building_floating_text(instance_id, String(result.get("message", "")), _result_text_color(result))


## 在建筑处显示固定失败文案。
##
## @param instance_id 建筑实例标识。
## @param message 失败文案。
## @return 无返回值。
func _show_building_failure(instance_id: int, message: String) -> void:
	_show_building_floating_text(instance_id, message, FAILURE_TEXT_COLOR)


## 返回服务结果对应的提示颜色。
##
## 服务的 message 同时承载成功（已放置 / 已拆除）与失败（这里已有建筑 / 不能拆除）文案，
## 因此不能一律用红色，否则「已放置」这类成功提示会被显示成报错。
##
## @param result 服务返回的 success/message 字典。
## @return 成功为白色，失败为红色。
func _result_text_color(result: Dictionary) -> Color:
	return SUCCESS_TEXT_COLOR if bool(result.get("success", false)) else FAILURE_TEXT_COLOR


## 读取建筑的世界坐标。
##
## 飘字锚点用世界坐标而不是建筑视图节点：拆除成功会同步重建 _views 并释放旧节点，
## 传节点会让提示回退到鼠标位置，而不是停在被拆的建筑处。
##
## @param instance_id 建筑实例标识。
## @return 建筑中心的世界坐标；记录已不存在时退回房间原点。
func _building_world_position(instance_id: int) -> Vector2:
	if not is_instance_valid(_room_scene) or not is_instance_valid(_store):
		return Vector2.ZERO
	for record: Dictionary in _store.call("GetBuildings", _room):
		if int(record["id"]) == instance_id:
			return _room_scene.to_global(record["position"])
	return _room_scene.global_position


## 判断飘字服务是否可用。
##
## 用 has_method 做鸭子类型，使服务缺失或版本不匹配时只降级提示、不影响交互判定本身。
##
## @return 服务存在且实现了两个飘字入口时为 true。
func _has_floating_text() -> bool:
	if _floating_text == null or not is_instance_valid(_floating_text):
		return false
	return _floating_text.has_method(FLOATING_TEXT_SHOW_AT_TARGET) \
		and _floating_text.has_method(FLOATING_TEXT_SHOW_AT_WORLD)
