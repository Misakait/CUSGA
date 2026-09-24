extends Node

## 建筑系统回归场景；在 Godot 中打开同名 .tscn 并按 F6 运行，无需 MCP。
## 使用生产资源和服务，覆盖库存事务、房间状态、按键门禁与可扩展策略。

## 生产规则服务。
const SERVICE: GDScript = preload("res://core/building/building_service.gd")
## 生产建筑仓库。
const STORE: GDScript = preload("res://core/building/room_building_store.gd")
## 生产输入协调器。
const CONTROLLER: GDScript = preload("res://core/building/building_controller.gd")
## 生产库存组件。
const INVENTORY: GDScript = preload("res://entities/components/inventory_component.gd")
## 生产生命组件。
const HEALTH: GDScript = preload("res://entities/components/health_component.gd")
## 生产合成服务。
const CRAFTING: GDScript = preload("res://core/crafting/crafting_service.gd")
## 实际篝火资产。
const CAMPFIRE: Resource = preload("res://items/environment/campfire.tres")
## 实际篝火配方。
const RECIPE: Resource = preload("res://resources/recipe/res/campfire_recipe.tres")
## 真实背包及槽位场景，用于验证菜单入口与拖拽互斥。
const INVENTORY_UI: PackedScene = preload("res://scenes/inventory/inventory_ui.tscn")
## 真实长按控制器，确保拆除复用已有圆环与 Tween 生命周期。
const HOLD: GDScript = preload("res://core/gameflow/world_hold_interaction_controller.gd")
## 真实 HUD 圆环，为隔离测试提供完整依赖。
const INDICATOR: GDScript = preload("res://core/ui/hud/world_hold_progress_indicator.gd")
## 测试场景的可建地面。
const BOUNDS: Rect2 = Rect2(0, 0, 1280, 720)
## 汇总失败原因，最后统一输出。
var _failures: Array[String] = []
## 已执行断言数，用于结果报告。
var _checks: int = 0


## 时间探针，隔离真正的天数、饥饿和天赋副作用。
class TimeProbe extends Node:
	## 累计消耗的行动值。
	var total: int = 0
	## 结算调用次数。
	var calls: int = 0
	## 记录时间；amount 为消耗量，无返回值。
	func PassTime(amount: int) -> void:
		total += amount
		calls += 1


## 测试策略证明新增建筑无需在服务中添加 CardId 分支。
class CountingInteraction extends "res://resources/buildings/building_interaction.gd":
	## context/state 为扩展协议输入，返回空串表示可执行。
	func get_unavailable_reason(_context: Dictionary, _state: Dictionary) -> String:
		return ""
	## context 为上下文，state 为实例状态，返回成功结果。
	func execute(_context: Dictionary, state: Dictionary) -> Dictionary:
		state["uses"] = int(state.get("uses", 0)) + 1
		return {"success": true, "message": "扩展效果"}


## 供控制器查询世界状态的最小公开门禁。
class WorldProbe extends Node:
	## 模拟战斗或过场锁。
	var available: bool = true
	## 无参数，返回是否开放局外交互。
	func CanUseWorld() -> bool:
		return available and not get_tree().paused


## 提供棋盘协议，避免测试需要生成随机地图。
class BoardProbe extends Node2D:
	## 记录生成到地面的物品堆叠，验证拆除不会直接塞进背包。
	var spawned_drops: Array = []
	## 记录掉落起点，验证使用被拆建筑的世界位置。
	var drop_origin: Vector2
	## 无参数，返回空卡牌数组。
	func GetActiveCardsSnapshot() -> Array[Node2D]:
		return []
	## stacks 为掉落堆叠，origin 为世界位置，无返回值。
	func SpawnLootCards(stacks: Array, origin: Vector2) -> void:
		spawned_drops.append_array(stacks)
		drop_origin = origin


## 只替换外部鼠标采样，目标选择和拆除业务仍执行生产实现。
class ControllerInputProbe extends "res://core/building/building_controller.gd":
	## 确定的鼠标世界坐标，避免测试移动真实桌面鼠标。
	var pointer: Vector2 = Vector2.ZERO
	## 模拟左键是否持续按住。
	var held: bool = false
	## 无参数，返回测试注入的鼠标坐标。
	func _mouse_world_position() -> Vector2:
		return pointer
	## 无参数，返回测试注入的持续按键状态。
	func _is_demolition_button_pressed() -> bool:
		return held


## 提供玩家端口，保留生产信号名和组件字段。
class PortProbe extends Node:
	## 建筑牌使用请求。
	signal BuildingPlacementRequested(item: Resource)
	## 背包组件。
	var PlayerInventory: Node
	## 生命组件。
	var PlayerHealth: Node
	## 角色数值节点。
	var Player: Node
	## 收到的放置请求，不代替建筑服务扣除库存。
	var placement_requests: Array[Resource] = []
	## item 为建筑牌，返回请求是否已转发。
	func RequestPlaceBuilding(item: Resource) -> bool:
		placement_requests.append(item)
		BuildingPlacementRequested.emit(item)
		return true


## 提供当前房间视图协议。
class MapViewProbe extends Node2D:
	## 房间切换广播。
	signal on_entered_room(position: Vector2i, scene: Node2D)
	## 当前地图坐标。
	var current_position: Vector2i = Vector2i.ZERO
	## 当前房间实体。
	var current_scene: Node2D


## 提供地图尺寸协议。
class MapModelProbe extends Node:
	## 与生产地图一致的房间尺寸。
	var room_size: Vector2 = Vector2(1280, 720)


## 场景就绪后启动测试；无参数，无返回值。
func _ready() -> void:
	call_deferred("_run")


## 按依赖顺序运行，结果在输出窗口和测试场景中显示。
func _run() -> void:
	_check(InputMap.has_action("interact_building"), "项目必须注册建筑交互动作")
	# 验证实际 InputMap，而不是只使用能绕过键位映射的动作事件。
	var has_f_key: bool = false
	for input_event: InputEvent in InputMap.action_get_events("interact_building"):
		if input_event is InputEventKey and input_event.physical_keycode == KEY_F:
			has_f_key = true
	_check(has_f_key, "建筑交互必须绑定物理 F 键")
	_test_recipe_and_crafting()
	_test_placement_and_room_state()
	_test_rest_and_extension()
	_test_demolition_service()
	await _test_item_menu()
	await _test_controller_inputs()
	# 展示真实执行结果，失败不提前中断后续断言。
	var report: Label = Label.new()
	report.text = "建筑测试：%d 项断言，%d 项失败" % [_checks, _failures.size()]
	add_child(report)
	print("[BuildingSystem] ", report.text)
	for message: String in _failures:
		push_error(message)


## 验证生产配方实际扣除三树枝一火，并挂入角色的配方书。
func _test_recipe_and_crafting() -> void:
	# 当前用例的生产库存组件，避免改变真实玩家背包。
	var inventory: Node = _make_inventory()
	# 实际合成服务，用于验证配方完整事务而非模拟算式。
	var crafting: RefCounted = CRAFTING.new()
	# 实际配方材料列表，顺序对应树枝与火。
	var inputs: Array = RECIPE.get("Inputs")
	# 配方引用的生产树枝资源，保留库存要求的资源身份。
	var branch: Resource = inputs[0].get("RequiredItem")
	# 配方引用的火资源，验证失败时不得消耗。
	var fire: Resource = inputs[1].get("RequiredItem")
	inventory.call("AddItem", branch, 2)
	inventory.call("AddItem", fire, 1)
	_check(not crafting.call("TryCraft", inventory, RECIPE, 1), "不足三树枝必须拒绝合成")
	_check(inventory.call("ItemCnt", fire) == 1, "失败合成不得消耗火")
	inventory.call("AddItem", branch, 1)
	_check(crafting.call("TryCraft", inventory, RECIPE, 1), "三树枝一火必须合成成功")
	_check(inventory.call("ItemCnt", CAMPFIRE) == 1, "配方必须产出一张可放置的篝火")
	_check(inventory.call("ItemCnt", branch) == 0 and inventory.call("ItemCnt", fire) == 0,
		"成功合成恰好扣除三树枝一火")
	_check(CAMPFIRE.call("IsBuildingCard"), "篝火资产必须符合建筑数据协议")
	# 不挂树的角色场景也必须携带生产配方，避免仅测试孤立资产。
	var player: Node = (load("res://scenes/player_scenes/player.tscn") as PackedScene).instantiate()
	# 角色场景实际配置的配方书，用于确认功能入口已接线。
	var book: Resource = player.get_node("Components/CraftingComponent").get("RecipeBook")
	_check((book.get("Recipes") as Array).has(RECIPE), "角色配方书必须注册篝火配方")
	player.free()
	inventory.free()


## 验证放置事务、非法落点、房间隔离与实例状态不会共享。
func _test_placement_and_room_state() -> void:
	# 当前用例的生产库存组件，避免改变真实玩家背包。
	var inventory: Node = _make_inventory()
	# 独立规则服务实例，避免不同用例共享事务锁。
	var service: RefCounted = SERVICE.new()
	# 当前测试独立的房间建筑仓库。
	var store: Node = STORE.new()
	inventory.call("AddItem", CAMPFIRE, 3)
	# 第一栋建筑的放置结果，用于检查扣牌和状态隔离。
	var first: Dictionary = service.call("TryPlace", CAMPFIRE, Vector2i.ZERO,
		Vector2(200, 200), BOUNDS, inventory, store)
	_check(first["success"], "合法位置必须可以放置")
	_check(inventory.call("ItemCnt", CAMPFIRE) == 2, "成功放置只消耗一张牌")
	for point: Vector2 in [Vector2(200, 200), Vector2(10, 10), Vector2(-100, 100)]:
		# 无效落点的实际执行结果，必须保持库存不变。
		var rejected: Dictionary = service.call("TryPlace", CAMPFIRE, Vector2i.ZERO,
			point, BOUNDS, inventory, store)
		_check(not rejected["success"], "重叠或越界落点必须拒绝")
	_check(inventory.call("ItemCnt", CAMPFIRE) == 2, "无效放置不得扣牌")
	# 与地形矩形重叠时的执行结果。
	var blocked: Dictionary = service.call("TryPlace", CAMPFIRE, Vector2i.ZERO,
		Vector2(400, 200), BOUNDS, inventory, store, [Rect2(350, 150, 100, 100)])
	_check(not blocked["success"], "地形占地必须阻挡放置")
	# 另一房间中的同类建筑，用于验证房间隔离。
	var second: Dictionary = service.call("TryPlace", CAMPFIRE, Vector2i(1, 0),
		Vector2(200, 200), BOUNDS, inventory, store)
	_check(second["success"], "不同房间可以使用相同局部坐标")
	first["record"]["state"]["fuel"] = 7
	_check(not second["record"]["state"].has("fuel"), "同类建筑必须持有独立状态")
	_check((store.call("GetBuildings", Vector2i.ZERO) as Array)[0]["state"]["fuel"] == 7,
		"离开后重新读取房间必须保留建筑状态")
	_check(store.call("RemoveBuilding", Vector2i.ZERO, first["record"]["id"]), "拆除接口按实例移除")
	_check((store.call("GetBuildings", Vector2i(1, 0)) as Array).size() == 1, "拆除不影响其他房间")
	inventory.call("TryRemoveItem", CAMPFIRE, 1)
	# 库存已移除建筑牌后的执行结果，必须拒绝凭空建造。
	var missing: Dictionary = service.call("TryPlace", CAMPFIRE, Vector2i.ZERO,
		Vector2(200, 200), BOUNDS, inventory, store)
	_check(not missing["success"], "预览后库存已失效时不得凭空建造")
	store.free()
	inventory.free()


## 验证实际回血、封顶、满血正常收费、死亡拒绝以及可替换策略。
func _test_rest_and_extension() -> void:
	# 独立规则服务实例，避免不同用例共享事务锁。
	var service: RefCounted = SERVICE.new()
	# 当前用例的生产生命组件，初始值由夹具显式设置。
	var health: Node = _make_health()
	# 隔离的行动值探针，记录结算量和调用次数。
	var time: TimeProbe = TimeProbe.new()
	# 建筑实例记录，保存配置身份和独立运行时状态。
	var record: Dictionary = {"data": CAMPFIRE, "state": {}}
	# 生命变化会同步通知外部监听者，必须证明通知中的重入不会再次回血或扣费。
	var reentry: Dictionary = {"attempts": 0, "accepted": false}
	# 同步生命信号回调，主动尝试重入以验证事务锁。
	var on_healed: Callable = func(_current: int, _maximum: int) -> void:
		reentry["attempts"] += 1
		# 信号回调中的第二次使用结果，必须被服务拒绝。
		var nested: Dictionary = service.call("TryInteract", record, {"health": health}, time)
		reentry["accepted"] = bool(nested["success"])
	health.connect("ValueChanged", on_healed)
	# 实际执行结果，成功标志决定后续扣费与反馈。
	var result: Dictionary = service.call("TryInteract", record, {"health": health}, time)
	_check(result["success"] and health.get("CurrentValue") == 700, "篝火必须恢复 200 生命")
	_check(time.total == 50 and time.calls == 1, "一次成功使用必须且只能消耗 50 行动值")
	_check(reentry["attempts"] == 1 and not reentry["accepted"], "生命信号回调不能重入同一交互")
	health.disconnect("ValueChanged", on_healed)
	health.set("CurrentValue", 950)
	result = service.call("TryInteract", record, {"health": health}, time)
	_check(result["healed"] == 50 and health.get("CurrentValue") == 1000, "回血不得超过生命上限")
	_check(time.total == 100, "不足 200 的有效回血仍按完整 50 行动值收费")
	result = service.call("TryInteract", record, {"health": health}, time)
	_check(result["success"] and result["healed"] == 0 and time.total == 150,
		"满血也能休息，生命不超上限且照常消耗 50 行动值")
	_check(health.get("CurrentValue") == 1000 and time.calls == 3, "满血休息只推进一次时间")
	health.set("CurrentValue", 0)
	result = service.call("TryInteract", record, {"health": health}, time)
	_check(not result["success"] and time.total == 150, "死亡角色不得复活或扣费")
	# 替换为未知 CardId 与状态型策略，验证服务完全不依赖篝火身份。
	var custom: Resource = CAMPFIRE.duplicate()
	# 另一种建筑策略，用于验证无需修改核心分支即可扩展。
	var effect: CountingInteraction = CountingInteraction.new()
	effect.ActionPointCost = 7
	custom.set("CardId", &"future_workshop")
	custom.set("Interaction", effect)
	record = {"data": custom, "state": {}}
	result = service.call("TryInteract", record, {}, time)
	_check(result["success"] and record["state"]["uses"] == 1 and time.total == 157,
		"新建筑策略必须无需修改系统即可执行并保存独立状态")
	time.free()
	health.free()


## 验证真实控制器对最近目标、F 键、模态界面、距离、预览与切房间的处理。
func _test_controller_inputs() -> void:
	# 本用例的场景节点容器，结束后统一释放。
	var fixture: Node = Node.new()
	add_child(fixture)
	# 当前用例的生产库存组件，避免改变真实玩家背包。
	var inventory: Node = _make_inventory()
	# 当前用例的生产生命组件，初始值由夹具显式设置。
	var health: Node = _make_health()
	# 测试玩家端口，字段和信号沿用生产协议。
	var port: PortProbe = PortProbe.new()
	port.PlayerInventory = inventory
	port.PlayerHealth = health
	port.Player = fixture
	fixture.add_child(port)
	# 隔离的行动值探针，记录结算量和调用次数。
	var time: TimeProbe = TimeProbe.new()
	fixture.add_child(time)
	# 测试世界门禁，切换可用标志模拟战斗与过场。
	var world: WorldProbe = WorldProbe.new()
	fixture.add_child(world)
	# 复用生产圆环计时；测试只注入路径，不伪造完成回调。
	var hold: Node = HOLD.new()
	hold.name = "WorldHoldInteractionController"
	# 生产计时器需要真实进度视图，避免假探针漏掉圆环接线错误。
	var indicator: Control = INDICATOR.new()
	indicator.name = "Indicator"
	hold.add_child(indicator)
	hold.set("progress_indicator_path", ^"Indicator")
	world.add_child(hold)
	# 测试地图模型，为落点校验提供房间尺寸。
	var model: MapModelProbe = MapModelProbe.new()
	fixture.add_child(model)
	# 测试房间根节点，负责局部与世界坐标转换。
	var room: Node2D = Node2D.new()
	fixture.add_child(room)
	# 测试房间视图，提供当前房间与切换信号。
	var map_view: MapViewProbe = MapViewProbe.new()
	map_view.current_scene = room
	fixture.add_child(map_view)
	# 当前测试独立的房间建筑仓库。
	var store: Node = STORE.new()
	fixture.add_child(store)
	# 测试棋盘容器，隔离随机地形生成。
	var board: BoardProbe = BoardProbe.new()
	fixture.add_child(board)
	# 建筑表现层，测试切换房间时能否重建实例。
	var buildings_root: Node2D = Node2D.new()
	board.add_child(buildings_root)
	# 目标实体的碰撞节点；射线需排除目标自身。
	var body: CharacterBody2D = CharacterBody2D.new()
	body.collision_layer = 16
	body.position = Vector2(200, 200)
	fixture.add_child(body)
	# 玩家的实际碰撞节点，用于覆盖大于脚下保护半径的情况。
	var collision: CollisionShape2D = CollisionShape2D.new()
	# 本次独立碰撞形状，避免共享形状被其他实例修改。
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(100, 140)
	collision.shape = shape
	body.add_child(collision)
	# 测试模态 UI 容器，打开子面板时应阻止建筑交互。
	var overlay: Control = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fixture.add_child(overlay)
	# 测试提示标签，保持生产控制器的完整场景依赖。
	var hint: Label = Label.new()
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fixture.add_child(hint)
	# 生产建筑协调器，通过注入路径接入测试夹具。
	var controller: ControllerInputProbe = ControllerInputProbe.new()
	# 路径全部注入探针，避免修改真实局内全局时间或世界节点。
	for binding: Array in [
		["PlayerBodyPath", body], ["GameplayPortPath", port], ["TimeSystemPath", time],
		["WorldCoordinatorPath", world], ["MapViewPath", map_view], ["MapModelPath", model],
		["StorePath", store], ["BuildingsRootPath", buildings_root], ["HintPath", hint], ["OverlayPath", overlay]]:
		controller.set(binding[0], binding[1].get_path())
	fixture.add_child(controller)
	await get_tree().process_frame
	# 关闭自动刷新以便逐项改变夹具，输入入口仍直接执行生产代码。
	controller.set_process(false)
	store.call("AddBuilding", Vector2i.ZERO, CAMPFIRE, Vector2(300, 200))
	store.call("AddBuilding", Vector2i.ZERO, CAMPFIRE, Vector2(100, 240))
	await get_tree().physics_frame
	# 单次建筑交互动作事件，模拟有效 F 按下。
	var key: InputEventAction = InputEventAction.new()
	key.action = &"interact_building"
	key.pressed = true
	controller.call("_unhandled_input", key)
	_check(time.total == 50 and health.get("CurrentValue") == 700,
		"靠近按 F 只使用一个最近建筑，不同时使用范围内所有建筑")
	# 键盘长按重复事件，必须被输入门禁忽略。
	var echo: InputEventKey = InputEventKey.new()
	echo.physical_keycode = KEY_F
	echo.pressed = true
	echo.echo = true
	controller.call("_unhandled_input", echo)
	_check(time.total == 50, "长按 F 的重复事件不得重复扣费")
	world.available = false
	controller.call("_unhandled_input", key)
	_check(time.total == 50, "战斗或过场期间禁止建筑交互")
	world.available = true
	# 可见模态界面，验证背包类 UI 打开时不会顺带使用建筑。
	var modal: Control = Control.new()
	overlay.add_child(modal)
	controller.call("_unhandled_input", key)
	_check(time.total == 50, "模态 UI 打开时禁止建筑交互")
	modal.hide()
	body.position = Vector2(900, 500)
	controller.call("_unhandled_input", key)
	_check(time.total == 50, "超出建筑范围禁止远程回血")
	body.position = Vector2(200, 200)
	inventory.call("AddItem", CAMPFIRE, 1)
	controller.call("BeginPlacement", CAMPFIRE)
	_check(controller.get("_placing_data") == CAMPFIRE, "建筑请求必须进入预览")
	_check(not String(controller.call("_placement_failure", Vector2(230, 260))).is_empty(),
		"放置必须避开完整玩家碰撞体")
	controller.call("CancelPlacement")
	_check(inventory.call("ItemCnt", CAMPFIRE) == 1, "取消预览不得消耗牌")
	controller.call("_on_room_entered", Vector2i(1, 0), room)
	_check((controller.get("_views") as Dictionary).is_empty(), "切房间后旧建筑不可交互")
	controller.call("_on_room_entered", Vector2i.ZERO, room)
	_check((controller.get("_views") as Dictionary).size() == 2, "返回房间必须重建原有建筑")
	# 缩短真实等待，保留生产时长配置独立性与真实 Tween 完成逻辑。
	var quick: Resource = CAMPFIRE.duplicate()
	quick.set("DemolitionHoldSeconds", 0.05)
	# 读取权威记录，使用真实实例标识参与取消与重复提交测试。
	var records: Array = store.call("GetBuildings", Vector2i.ZERO)
	# 第一栋位于鼠标测试落点，另一栋应始终保留。
	var target: Dictionary = records[0]
	target["data"] = quick
	controller.pointer = Vector2(300, 200)
	controller.held = true
	# 通过生产鼠标入口开始，验证命中建筑才能触发拆除。
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	controller.call("_input", press)
	_check(hold.get("is_holding") and indicator.get("is_hold_progress_visible"),
		"长按拆除必须显示共享进度圆环")
	# 松开必须立刻撤销，不能等到下一帧碰巧清理。
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	controller.call("_input", release)
	await get_tree().create_timer(0.08).timeout
	_check((store.call("GetBuildings", Vector2i.ZERO) as Array).size() == 2
		and board.spawned_drops.is_empty(), "提前松开不拆建筑也不生成掉落")
	controller.call("_begin_demolition", target)
	controller.pointer = Vector2(100, 240)
	controller.call("_process", 0.01)
	_check(not hold.get("is_holding"), "移开鼠标或换目标必须取消拆除")
	controller.pointer = Vector2(300, 200)
	controller.call("_begin_demolition", target)
	modal.show()
	await get_tree().create_timer(0.08).timeout
	_check(board.spawned_drops.is_empty(), "完成瞬间打开界面也不能误拆")
	modal.hide()
	controller.call("_begin_demolition", target)
	world.available = false
	await get_tree().create_timer(0.08).timeout
	_check(board.spawned_drops.is_empty(), "长按完成时世界已关闭不能拆除")
	world.available = true
	controller.call("_begin_demolition", target)
	body.position = Vector2(900, 500)
	await get_tree().create_timer(0.08).timeout
	_check(board.spawned_drops.is_empty(), "长按中走远必须取消拆除")
	body.position = Vector2(200, 200)
	controller.call("_begin_demolition", target)
	controller.call("_notification", NOTIFICATION_PAUSED)
	_check(not hold.get("is_holding"), "暂停必须清理拆除进度")
	controller.call("_begin_demolition", target)
	controller.call("_unhandled_input", key)
	_check(not hold.get("is_holding") and time.total == 100, "按 F 使用建筑会撤销尚未完成的拆除")
	controller.call("_begin_demolition", target)
	controller.call("_on_room_entered", Vector2i(1, 0), room)
	await get_tree().create_timer(0.08).timeout
	_check(board.spawned_drops.is_empty(), "切换房间不能让旧拆除回调结算")
	controller.call("_on_room_entered", Vector2i.ZERO, room)
	await get_tree().physics_frame
	controller.call("_begin_demolition", target)
	await get_tree().create_timer(0.08).timeout
	_check((store.call("GetBuildings", Vector2i.ZERO) as Array).size() == 1,
		"完整长按只拆除鼠标指向的一栋建筑")
	_check(board.spawned_drops.size() == 1 and board.drop_origin == Vector2(300, 200),
		"拆除掉落经棋盘端口在原建筑世界位置生成")
	_check(time.total == 100, "拆除的真实秒数不能作为行动值扣费")
	_check(inventory.call("ItemCnt", RECIPE.get("Inputs")[0].get("RequiredItem")) == 0,
		"拆除掉落留在地面，不直接加入背包")
	controller.call("_complete_demolition")
	_check(board.spawned_drops.size() == 1, "重复完成回调不能重复掉落")
	controller.call("_on_room_entered", Vector2i(1, 0), room)
	controller.call("_on_room_entered", Vector2i.ZERO, room)
	_check((controller.get("_views") as Dictionary).size() == 1, "返回房间不能复活已拆除建筑")
	fixture.queue_free()
	health.queue_free()
	inventory.queue_free()
	await get_tree().process_frame


## 验证拆除的配置扩展、幂等性和仓库信号重入保护。
func _test_demolition_service() -> void:
	# 独立生产服务与仓库，不依赖地图或鼠标输入。
	var service: RefCounted = SERVICE.new()
	# 独立仓库避免影响主场景建筑和其它用例。
	var store: Node = STORE.new()
	# 使用实际篝火配置，验证材料来自生产资源而非测试假值。
	var record: Dictionary = store.call("AddBuilding", Vector2i.ZERO, CAMPFIRE, Vector2(200, 200))
	# 仓库移除信号同步重入，必须拒绝第二次掉落结算。
	var reentry: Dictionary = {"accepted": false, "calls": 0}
	# 在移除信号中主动再次拆除，模拟外部订阅者同步重入。
	var callback: Callable = func(_room: Vector2i) -> void:
		reentry["calls"] += 1
		# 重入结果不得成功，也不得再次返回掉落。
		var nested: Dictionary = service.call("TryDemolish", Vector2i.ZERO, record["id"], store)
		reentry["accepted"] = nested["success"]
	store.connect("BuildingsChanged", callback)
	# 错误房间与正确房间共用实例标识，确保房间边界参与判定。
	var wrong_room: Dictionary = service.call("TryDemolish", Vector2i(1, 0), record["id"], store)
	_check(not wrong_room["success"], "不能从错误房间删除建筑")
	# 首次合法拆除结果用于核对真实掉落物品和数量。
	var result: Dictionary = service.call("TryDemolish", Vector2i.ZERO, record["id"], store)
	_check(result["success"] and (result["drops"] as Array).size() == 1, "篝火拆除生成一个掉落堆叠")
	if result["success"] and (result["drops"] as Array).size() == 1:
		# 掉落堆叠保持原始资源身份，确保可以回到现有合成材料链。
		var stack: RefCounted = result["drops"][0]
		_check(stack.get("Item") == RECIPE.get("Inputs")[0].get("RequiredItem")
			and stack.get("Amount") == 1, "篝火掉落恰好一个配方同源树枝")
	_check(reentry["calls"] == 1 and not reentry["accepted"], "移除信号不得重入拆除事务")
	store.disconnect("BuildingsChanged", callback)
	result = service.call("TryDemolish", Vector2i.ZERO, record["id"], store)
	_check(not result["success"] and not result.has("drops"), "过期拆除请求不得再次掉落")
	# 不可拆和无掉落建筑都经配置控制，不添加具体建筑 ID 分支。
	var custom: Resource = CAMPFIRE.duplicate()
	custom.set("Destructible", false)
	record = store.call("AddBuilding", Vector2i.ZERO, custom, Vector2(200, 200))
	result = service.call("TryDemolish", Vector2i.ZERO, record["id"], store)
	_check(not result["success"] and (store.call("GetBuildings", Vector2i.ZERO) as Array).size() == 1,
		"不可拆配置必须保留建筑")
	custom.set("Destructible", true)
	custom.set("DestructionLoot", null)
	result = service.call("TryDemolish", Vector2i.ZERO, record["id"], store)
	_check(result["success"] and (result["drops"] as Array).is_empty(), "无掉落配置也能正常拆除")
	store.free()


## 验证生产槽位左键弹窗、选择后放置、右键无效和拖拽快捷键兼容。
func _test_item_menu() -> void:
	# 使用真实背包 UI 场景和库存，仅替换放置请求的接收端口。
	var fixture: Node = Node.new()
	add_child(fixture)
	# 菜单操作只转发请求，物品始终保留到真正落地确认。
	var inventory: Node = _make_inventory()
	inventory.call("AddItem", CAMPFIRE, 1)
	# 只记录 UI 发出的建筑请求，不执行地图放置。
	var port: PortProbe = PortProbe.new()
	fixture.add_child(port)
	# 使用生产面板初始化与槽位生成逻辑，验证实际入口接线。
	var ui: Control = INVENTORY_UI.instantiate() as Control
	ui.set("GameplayPortPath", port.get_path())
	fixture.add_child(ui)
	ui.call("_bind_player_inventory", inventory)
	ui.call("_rebind_inventory_slots")
	ui.show()
	await get_tree().process_frame
	# 通过生成槽位的生产 GUI 输入入口触发，避免只测试父面板私有方法。
	var slot: Control = (ui.get("_slot_views") as Array)[0]
	# 读取实际菜单而非伪造选择结果，验证中文动作项存在。
	var menu: PopupMenu = ui.get("_item_action_menu") as PopupMenu
	# 复用成对的鼠标按下/松开事件，覆盖点击与拖拽的区别。
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.position = Vector2(5, 5)
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	slot.call("_gui_input", click)
	_check(not menu.visible and port.placement_requests.is_empty(), "右键物品不再直接进入放置")
	click.button_index = MOUSE_BUTTON_LEFT
	slot.call("_gui_input", click)
	_check(not menu.visible, "左键按下不抢占拖拽")
	click.pressed = false
	slot.call("_gui_input", click)
	_check(menu.visible and menu.get_item_text(menu.get_item_index(1)) == "放置",
		"普通左键点击建筑必须弹出放置选项")
	_check(port.placement_requests.is_empty() and ui.visible, "打开选项不提前放置或关闭背包")
	menu.id_pressed.emit(1)
	_check(port.placement_requests.size() == 1 and not ui.visible,
		"选择放置后关闭背包并只发出一次放置请求")
	_check(inventory.call("ItemCnt", CAMPFIRE) == 1, "选择放置不提前消耗建筑牌")
	ui.show()
	click.pressed = true
	slot.call("_gui_input", click)
	slot.call("_notification", Control.NOTIFICATION_DRAG_BEGIN)
	click.pressed = false
	slot.call("_gui_input", click)
	_check(not menu.visible and slot.call("_build_drag_data") != null, "拖拽仍可生成载荷且不会误弹菜单")
	# 保留 Shift/Alt 原有快捷路径，释放左键后也不能弹菜单。
	var shortcuts: Array = []
	slot.call("SetShortcutHandler", func(_slot: Object, kind: int) -> void: shortcuts.append(kind))
	for use_shift: bool in [true, false]:
		click.shift_pressed = use_shift
		click.alt_pressed = not use_shift
		click.pressed = true
		slot.call("_gui_input", click)
		click.pressed = false
		slot.call("_gui_input", click)
	_check(shortcuts == [0, 1] and not menu.visible, "Shift/Alt 快捷键不触发物品菜单")
	click.shift_pressed = false
	click.alt_pressed = false
	click.pressed = true
	slot.call("_gui_input", click)
	click.pressed = false
	slot.call("_gui_input", click)
	inventory.call("TryRemoveItem", CAMPFIRE, 1)
	menu.id_pressed.emit(1)
	_check(not menu.visible and port.placement_requests.size() == 1,
		"库存已改变时旧菜单不能放置消失的建筑牌")
	fixture.queue_free()
	inventory.queue_free()
	await get_tree().process_frame


## 创建拥有足够槽位的生产库存。
func _make_inventory() -> Node:
	# 当前用例的生产库存组件，避免改变真实玩家背包。
	var inventory: Node = INVENTORY.new()
	add_child(inventory)
	return inventory


## 创建上限 1000、当前 500 的生产生命组件。
func _make_health() -> Node:
	# 当前用例的生产生命组件，初始值由夹具显式设置。
	var health: Node = HEALTH.new()
	add_child(health)
	health.call("InitializeMax", 1000)
	health.call("Subtract", 500)
	return health


## 记录一次断言；condition 为实际结果，message 为失败说明，无返回值。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
