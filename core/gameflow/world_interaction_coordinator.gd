extends Node

## 局外世界交互协调器 GDScript 生产实现，等价迁移自 core/gameflow/WorldInteractionCoordinator.cs。
##
## 职责：集中处理棋盘卡牌的点击/长按/生成信号、局外地图长按、遭遇请求转发，以及进入战斗时的
## 过场、背景复制与世界视图显隐。四个只被本协调器使用的辅助类（战斗场景表现层、过场适配器、
## 世界视图控制器、地形交互执行器）按“同名协议内联”的方式在本脚本内实现，避免为复用仅 C#
## 可见的普通类而新增跨语言桥接层。
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。
##
## 迁移边界：生产地形实例（terrain_instance.gd）、棋盘控制器（board_controller.gd）、
## GameplayPort（gameplay_port.gd）、EncounterManager（encounter_manager.gd）与过场
## Autoload（ScreenTransitions.gd）均已迁移，本脚本只按稳定信号名、方法名与字段名与它们交互。

## GameplayPort 的遭遇请求信号名。
const ENCOUNTER_REQUESTED_SIGNAL: StringName = &"EncounterRequested"
## 时间系统的累计时间变化信号名。
const TIME_CHANGED_SIGNAL: StringName = &"TimeChanged"
## 棋盘控制器的卡牌信号稳定名称（GDScript 信号没有生成的常量，必须集中保存）。
const BOARD_CARD_CLICKED_SIGNAL: StringName = &"CardClicked"
## 棋盘卡牌按下信号名。
const BOARD_CARD_PRESSED_SIGNAL: StringName = &"CardPressed"
## 棋盘卡牌抬起信号名。
const BOARD_CARD_RELEASED_SIGNAL: StringName = &"CardReleased"
## 棋盘卡牌生成信号名。
const BOARD_CARD_SPAWNED_SIGNAL: StringName = &"CardSpawned"
## 时间 Autoload 的固定挂载路径。
const TIME_SYSTEM_PATH: NodePath = ^"/root/TimeSystem"
## 战斗场景路径。
const BATTLE_SCENE_PATH: String = "res://scenes/battle_scenes/battle.tscn"
## 战斗场景的结束信号名。
const BATTLE_ENDED_SIGNAL: StringName = &"battle_ended"
## 生产 GDScript 战斗背景解析器脚本路径。
const MAP_BACKGROUND_RESOLVER_SCRIPT_PATH: String = "res://core/gameflow/UICurrentMapBackgroundResolver.gd"
## 怪物数据的跨语言字段协议：C# MonsterData 为 [Export]，GDScript monster_data.gd 为 @export。
## 判定只看字段面，不看类型名或脚本路径，避免把语言身份写进生产逻辑。
const MONSTER_DATA_REQUIRED_FIELDS: Array[StringName] = [
	&"MonsterName",
	&"ElementalProperty",
	&"SkillSet",
]
## 可重复采集协议的方法名（旧 C# 垫片用 PascalCase）。
## 两侧实现共用同一组协议方法，判定只看「有没有这些方法」，不看类型名或脚本路径，
## 因此 C# 垫片退役后本脚本仍可解析、无需再改。
const REUSABLE_GATHERING_CS_METHODS: Array[StringName] = [
	&"GetEffectiveTimeCost",
	&"CanHarvest",
]
## 可重复采集协议的方法名（生产 GDScript 用 snake_case）。
const REUSABLE_GATHERING_GD_METHODS: Array[StringName] = [
	&"get_effective_time_cost",
	&"can_harvest",
]
## 有效耗时协议在方法名数组中的下标。
const REUSABLE_GATHERING_TIME_COST_INDEX: int = 0
## 可采集判定协议在方法名数组中的下标。
const REUSABLE_GATHERING_CAN_HARVEST_INDEX: int = 1

## 驻守战斗结束后向地图通道控制器回传结果。
signal PassageGuardEncounterFinished(is_victory: bool)
## 局外长按完成时通知 GDScript 地图拥有者执行其保留的业务流程。
signal WorldHoldCompleted(owner: Node)

## 棋盘控制器节点路径。
@export var BoardControllerPath: NodePath = NodePath("")
## GameplayPort 节点路径。
@export var GameplayPortPath: NodePath = NodePath("")
## 背包飞入目标节点路径。
@export var BackpackFlyTargetPath: NodePath = NodePath("")
## 遭遇管理器节点路径。
@export var EncounterManagerPath: NodePath = NodePath("")
## 统一管理局外长按输入与圆环反馈的子组件路径。
@export var HoldInteractionControllerPath: NodePath = NodePath("WorldHoldInteractionController")
## 过场 Autoload 路径；旧 C# 未导出该字段，因此这里保持普通属性，不改变序列化面。
var ScreenTransitionsPath: NodePath = ^"/root/ScreenTransitions"

@export_group("World View")
## 世界根节点路径；战斗场景实例挂在其下。
@export var WorldRootPath: NodePath = NodePath("../..")
## 地图系统节点路径。
@export var MapSystemPath: NodePath = NodePath("../../MapSystem")
## 地图 CanvasLayer 路径。
@export var MapCanvasLayerPath: NodePath = NodePath("../../MapSystem/CanvasLayer")
## HUD CanvasLayer 路径。
@export var HudLayerPath: NodePath = NodePath("../../UI/HUDLayer")

## 棋盘控制器；只保留 Node 与信号/方法协议，兼容 C# 垫片与生产 GDScript。
var _board_controller: Node = null
## GameplayPort；只依赖稳定的属性、方法和信号协议。
var _gameplay_port: Node = null
## 背包飞入目标；缺失时掉落卡直接移除。
var _backpack_fly_target: Control = null
## 遭遇管理器；只依赖稳定的 Node 方法协议。
var _encounter_manager: Node = null
## 时间 Autoload；以稳定 Node 协议持有，兼容旧 C# 与生产 GDScript 实现。
var _time_system: Node = null
## 过场 Autoload。
var _screen_transitions: Node = null
## 世界根节点。
var _world_root: Node = null
## 地图系统节点，用于复制当前房间背景。
var _map_system: Node = null
## 统一处理地图按钮与棋盘地形之间互斥的长按状态。
var _hold_interaction_controller: Node = null

## 棋盘控制器四个信号的连接实例；退出时必须用同一实例断开。
var _board_card_clicked_callable: Callable = Callable()
## 棋盘卡牌按下信号连接实例。
var _board_card_pressed_callable: Callable = Callable()
## 棋盘卡牌抬起信号连接实例。
var _board_card_released_callable: Callable = Callable()
## 棋盘卡牌生成信号连接实例。
var _board_card_spawned_callable: Callable = Callable()
## GameplayPort 遭遇请求信号连接实例。
var _encounter_requested_callable: Callable = Callable()
## 时间系统时间变化信号连接实例。
var _time_changed_callable: Callable = Callable()

## 是否正处于进入战斗或退出战斗的过场中；旧 C# 用同一标志拒绝重复过渡。
var _is_transitioning: bool = false
## 最近一次战斗是否已经结束并完成过场。
var _battle_result_ready: bool = false
## 最近一次战斗结果（胜利为 true）。
var _battle_result: bool = false


## 返回局外操作是否可用；无参数，战斗、过场或暂停时返回 false。
## 建筑等扩展系统通过该接口查询，不读取协调器内部过场字段。
func CanUseWorld() -> bool:
	return is_inside_tree() and not get_tree().paused and not _is_transitioning \
		and is_instance_valid(_board_controller) and (_board_controller as CanvasItem).is_visible_in_tree()


## 进入场景树时解析导出路径、连接棋盘与遭遇/时间信号。
##
## @return 无返回值。
func _ready() -> void:
	_board_controller = get_node(BoardControllerPath)
	_gameplay_port = get_node(GameplayPortPath)
	_backpack_fly_target = get_node_or_null(BackpackFlyTargetPath) as Control
	_encounter_manager = get_node(EncounterManagerPath)
	_time_system = get_node_or_null(TIME_SYSTEM_PATH)
	_screen_transitions = get_node_or_null(ScreenTransitionsPath)
	_world_root = get_node(WorldRootPath)
	_map_system = get_node_or_null(MapSystemPath)
	_hold_interaction_controller = get_node(HoldInteractionControllerPath)

	_board_card_clicked_callable = Callable(self, "_on_board_card_clicked")
	_board_card_pressed_callable = Callable(self, "_on_board_card_pressed")
	_board_card_released_callable = Callable(self, "_on_board_card_released")
	_board_card_spawned_callable = Callable(self, "_on_board_card_spawned")
	_board_controller.connect(BOARD_CARD_CLICKED_SIGNAL, _board_card_clicked_callable)
	_board_controller.connect(BOARD_CARD_PRESSED_SIGNAL, _board_card_pressed_callable)
	_board_controller.connect(BOARD_CARD_RELEASED_SIGNAL, _board_card_released_callable)
	_board_controller.connect(BOARD_CARD_SPAWNED_SIGNAL, _board_card_spawned_callable)

	# GDScript 信号参数先以 Variant 接收，再在处理器里集中验证数组元素，避免泛型数组隐式封送。
	_encounter_requested_callable = Callable(self, "_on_encounter_requested")
	if not _gameplay_port.has_signal(ENCOUNTER_REQUESTED_SIGNAL):
		push_error("GameplayPort 缺少 EncounterRequested 信号，无法转发局外遭遇。")
	elif not _gameplay_port.is_connected(ENCOUNTER_REQUESTED_SIGNAL, _encounter_requested_callable):
		_gameplay_port.connect(ENCOUNTER_REQUESTED_SIGNAL, _encounter_requested_callable)

	_time_changed_callable = Callable(self, "_on_time_changed")
	if _time_system == null:
		push_error("WorldInteractionCoordinator 未找到 TimeSystem Autoload。")
	elif not _time_system.has_signal(TIME_CHANGED_SIGNAL):
		push_error("TimeSystem 缺少 TimeChanged 信号，无法刷新可重复采集状态。")
	elif not _time_system.is_connected(TIME_CHANGED_SIGNAL, _time_changed_callable):
		_time_system.connect(TIME_CHANGED_SIGNAL, _time_changed_callable)


## 退出场景树时解除全部信号连接并取消未完成的长按。
##
## @return 无返回值。
func _exit_tree() -> void:
	_disconnect_board_signal(BOARD_CARD_CLICKED_SIGNAL, _board_card_clicked_callable)
	_disconnect_board_signal(BOARD_CARD_PRESSED_SIGNAL, _board_card_pressed_callable)
	_disconnect_board_signal(BOARD_CARD_RELEASED_SIGNAL, _board_card_released_callable)
	_disconnect_board_signal(BOARD_CARD_SPAWNED_SIGNAL, _board_card_spawned_callable)

	if _gameplay_port != null and is_instance_valid(_gameplay_port):
		if _gameplay_port.is_connected(ENCOUNTER_REQUESTED_SIGNAL, _encounter_requested_callable):
			_gameplay_port.disconnect(ENCOUNTER_REQUESTED_SIGNAL, _encounter_requested_callable)

	if _time_system != null and is_instance_valid(_time_system):
		if _time_system.has_signal(TIME_CHANGED_SIGNAL):
			if _time_system.is_connected(TIME_CHANGED_SIGNAL, _time_changed_callable):
				_time_system.disconnect(TIME_CHANGED_SIGNAL, _time_changed_callable)

	_cancel_active_hold()


## 解除棋盘控制器的信号连接；只有在确实已连接时才断开，避免重复退出报错。
##
## @param signal_name 棋盘控制器上的信号名。
## @param callback 连接时使用的同一个回调实例。
## @return 无返回值。
func _disconnect_board_signal(signal_name: StringName, callback: Callable) -> void:
	if _board_controller == null or not is_instance_valid(_board_controller):
		return
	if not callback.is_valid():
		return
	if _board_controller.is_connected(signal_name, callback):
		_board_controller.disconnect(signal_name, callback)


## 监听全局鼠标松开，确保拖出目标范围后也会取消局外长按。
##
## @param event Godot 输入事件。
## @return 无返回值。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			_cancel_active_hold()


## 转发 GameplayPort 的局外遭遇请求。
##
## @param _terrain 本次遭遇所在的地形实例；战斗场景只使用卡组与怪物。
## @param battle_deck GDScript 传入的动态技能卡数组。
## @param monsters GDScript 传入的动态怪物数组。
## @param _message 遭遇提示文本；旧实现同样不在本入口使用。
## @return 无返回值。
func _on_encounter_requested(
	_terrain: Variant,
	battle_deck: Variant,
	monsters: Variant,
	_message: Variant
) -> void:
	var cards: Array[Resource] = []
	if battle_deck is Array:
		cards = _convert_skill_cards(battle_deck)
	var encounter_monsters: Array[Resource] = []
	if monsters is Array:
		encounter_monsters = _convert_monsters(monsters)

	await _enter_combat(cards, encounter_monsters)


## 为地图通道驻守怪物发起战斗，并在战斗结束后发出结果信号。
##
## @param monsters 通道驻守 encounter 配置出的怪物数组。
## @return 无返回值；过渡被拒绝时同步发出 false，保持旧 C# 的同步语义。
func RequestPassageGuardEncounter(monsters: Array) -> void:
	print("RequestPassageGuardEncounter: monsters = ", monsters)
	if _is_transitioning:
		PassageGuardEncounterFinished.emit(false)
		return

	var is_victory: bool = await _enter_combat_and_wait_for_result(
		_get_player_skill_cards(),
		_convert_monsters(monsters)
	)
	PassageGuardEncounterFinished.emit(is_victory)


## 为 GDScript GameplayPort 提供动态数组到 EncounterManager 倍率入口的安全桥。
##
## @param terrain 本次遭遇所在的地形实例。
## @param monsters GDScript 传入的动态怪物数组。
## @return 按原顺序过滤输入后，由 EncounterManager 生成的缩放怪物数组。
func ScaleEncounterMonsters(terrain: Variant, monsters: Array) -> Array:
	var filtered_monsters: Array = _convert_monsters(monsters)
	if _encounter_manager == null or not _encounter_manager.has_method("ScaleEncounterMonsters"):
		return filtered_monsters

	var scaled: Variant = _encounter_manager.call("ScaleEncounterMonsters", terrain, filtered_monsters)
	if scaled is Array:
		return scaled

	return filtered_monsters


## 为 GDScript 地图控件开始一个局外长按，并在进度填满后以信号通知对应拥有者。
##
## @param owner 本次长按的地图节点拥有者。
## @param action_point_cost 开始时快照的实际行动值消耗。
## @param progress_target 地图方向按钮中用于绘制圆环的可见目标节点。
## @return 无返回值。
func BeginWorldHoldForMap(owner: Node, action_point_cost: int, progress_target: Node) -> void:
	if _hold_interaction_controller == null or not is_instance_valid(_hold_interaction_controller):
		push_error("WorldInteractionCoordinator 未找到 WorldHoldInteractionController，无法开始局外长按。")
		return

	_hold_interaction_controller.call(
		"begin_hold",
		owner,
		action_point_cost,
		Callable(self, "_on_world_hold_completed").bind(owner),
		progress_target
	)


## 为 GDScript 地图控件取消指定拥有者的局外长按。
##
## @param owner 请求取消的地图或棋盘节点拥有者。
## @return 无返回值。
func CancelWorldHoldFor(owner: Node) -> void:
	if _hold_interaction_controller == null or not is_instance_valid(_hold_interaction_controller):
		return

	_hold_interaction_controller.call("cancel_hold_for", owner)


## 长按进度填满后向发起本次长按的地图拥有者广播完成事件。
##
## @param owner 完成本次长按的有效节点拥有者。
## @return 无返回值。
func _on_world_hold_completed(owner: Node) -> void:
	WorldHoldCompleted.emit(owner)


## 无条件取消当前长按，供场景退出与全局鼠标释放使用。
##
## @return 无返回值。
func _cancel_active_hold() -> void:
	if _hold_interaction_controller == null or not is_instance_valid(_hold_interaction_controller):
		return

	_hold_interaction_controller.call("cancel_active_hold")


## 处理棋盘卡牌点击：先尝试拾取掉落卡，再处理地形交互。
##
## @param card 被点击的棋盘卡视图。
## @return 无返回值。
func _on_board_card_clicked(card: Node2D) -> void:
	var loot: RefCounted = _read_ref_counted_property(card, "GetLootStackOrNull")
	if loot != null:
		_handle_loot_card_clicked(card, loot)
		return

	var terrain: RefCounted = _read_ref_counted_property(card, "GetTerrainInstanceOrNull")
	if terrain != null:
		if _get_interaction_action_point_cost(_get_terrain_interaction(terrain)) > 0:
			return

		_handle_terrain_card_clicked(card, terrain)


## 拾取掉落卡：先尝试放进背包，成功后按原动画飞入背包或直接移除。
##
## @param card 被点击的掉落卡。
## @param stack 卡牌携带的物品堆叠。
## @return 无返回值。
func _handle_loot_card_clicked(card: Node2D, stack: RefCounted) -> void:
	var add_result: Variant = _gameplay_port.call("TryAddItemToInventory", stack)
	var success: bool = add_result is bool and bool(add_result)
	if not success:
		return

	if _backpack_fly_target == null:
		_board_controller.call("RemoveCard", card)
		return

	# 飞入结束后才移除源卡，保持旧实现的“先动画再清卡”顺序。
	var target: Vector2 = _backpack_fly_target.get_global_rect().get_center()
	card.call("PlayFlyTo", target, Callable(self, "_on_loot_fly_finished").bind(card))


## 掉落卡飞入动画结束后移除源卡。
##
## @param card 已完成飞入动画的掉落卡。
## @return 无返回值。
func _on_loot_fly_finished(card: Node2D) -> void:
	if _board_controller == null or not is_instance_valid(_board_controller):
		return

	_board_controller.call("RemoveCard", card)


## 处理地形卡点击：触发等价旧 C# TerrainInteractionExecutor 的交互序列。
##
## @param card 被点击的地形卡。
## @param terrain 卡牌携带的地形实例。
## @return 无返回值。
func _handle_terrain_card_clicked(card: Node2D, terrain: RefCounted) -> void:
	_execute_terrain_interaction(card, terrain, null)


## 处理棋盘卡牌按下：可长按的地形开始统一长按，其余卡牌不响应。
##
## @param card 被按下的棋盘卡视图。
## @return 无返回值。
func _on_board_card_pressed(card: Node2D) -> void:
	if _hold_interaction_controller == null or not is_instance_valid(_hold_interaction_controller):
		return

	var holdable: Dictionary = _try_get_holdable_terrain(card)
	if not bool(holdable["ok"]):
		return

	var terrain: RefCounted = holdable["terrain"]
	var interaction: Resource = holdable["interaction"]
	var action_point_cost: int = int(holdable["action_point_cost"])
	# 圆环锚定在地形图标上；图标缺失时退回卡片自身，保持旧 C# 的兜底目标。
	var icon: Node = card.get_node_or_null("Icon") as Node
	var progress_target: Node = card if icon == null else icon
	_hold_interaction_controller.call(
		"begin_hold",
		card,
		action_point_cost,
		Callable(self, "_complete_terrain_hold").bind(card, terrain, interaction, action_point_cost),
		progress_target
	)


## 处理棋盘卡牌抬起：取消该卡牌持有的长按。
##
## @param card 被抬起的棋盘卡视图。
## @return 无返回值。
func _on_board_card_released(card: Node2D) -> void:
	if _hold_interaction_controller == null or not is_instance_valid(_hold_interaction_controller):
		return

	_hold_interaction_controller.call("cancel_hold_for", card)


## 处理棋盘卡牌生成：可重复采集地形按当前时间刷新可采集状态。
##
## @param card 新生成的棋盘卡视图。
## @return 无返回值。
func _on_board_card_spawned(card: Node2D) -> void:
	var reusable: Dictionary = _try_get_reusable_gathering(card)
	if not bool(reusable["ok"]):
		return

	_refresh_reusable_gathering_card(
		card,
		reusable["terrain"],
		reusable["interaction"],
		_get_current_total_time()
	)


## 处理累计时间变化：刷新棋盘上所有可重复采集地形的可采集状态。
##
## @param total_time_passed 当前游戏总时间点数。
## @param _current_day 当前游戏天数；棋盘刷新不需要。
## @param _is_night 当前是否夜晚；棋盘刷新不需要。
## @param _phase_progress 当前阶段进度；棋盘刷新不需要。
## @param _phase_length 当前阶段长度；棋盘刷新不需要。
## @return 无返回值。
func _on_time_changed(
	total_time_passed: int,
	_current_day: int,
	_is_night: bool,
	_phase_progress: int,
	_phase_length: int
) -> void:
	# 棋盘控制器已迁移为 GDScript，快照通过稳定方法协议返回 Godot 数组。
	var snapshot: Variant = _board_controller.call("GetActiveCardsSnapshot")
	if not (snapshot is Array):
		return

	for card_variant: Variant in snapshot:
		if not (card_variant is Node2D):
			continue
		var card: Node2D = card_variant
		if not is_instance_valid(card):
			continue

		var reusable: Dictionary = _try_get_reusable_gathering(card)
		if not bool(reusable["ok"]):
			continue

		_refresh_reusable_gathering_card(card, reusable["terrain"], reusable["interaction"], total_time_passed)


## 判断卡牌是否属于可长按地形，并返回长按所需的全部快照数据。
##
## @param card 待判断的棋盘卡视图。
## @return 含 ok 标志的字典；可长按时附带 terrain / interaction / action_point_cost。
func _try_get_holdable_terrain(card: Node2D) -> Dictionary:
	var terrain: RefCounted = _read_ref_counted_property(card, "GetTerrainInstanceOrNull")
	var interaction: Resource = _get_terrain_interaction(terrain)
	var action_point_cost: int = _get_interaction_action_point_cost(interaction)
	if terrain == null or interaction == null or action_point_cost <= 0:
		return {"ok": false}

	var result: Dictionary = {
		"ok": true,
		"terrain": terrain,
		"interaction": interaction,
		"action_point_cost": action_point_cost,
	}
	if not _is_reusable_gathering(interaction):
		return result

	# 可重复采集在按下时先刷新一次，只有仍可采集时才允许进入长按。
	var total_time_passed: int = _get_current_total_time()
	_refresh_reusable_gathering_card(card, terrain, interaction, total_time_passed)
	result["ok"] = _can_harvest(interaction, terrain, total_time_passed)
	return result


## 长按进度填满后执行地形交互；卡牌与地形在长按期间变化时放弃本次执行。
##
## @param card 触发长按的地形卡。
## @param terrain 按下时快照的地形实例。
## @param interaction 按下时快照的交互资源。
## @param action_point_cost 按下时快照的行动值消耗。
## @return 无返回值。
func _complete_terrain_hold(
	card: Node2D,
	terrain: RefCounted,
	interaction: Resource,
	action_point_cost: int
) -> void:
	if not is_instance_valid(card):
		return
	if card.call("GetTerrainInstanceOrNull") != terrain:
		return

	if _is_reusable_gathering(interaction):
		var total_time_passed: int = _get_current_total_time()
		if not _can_harvest(interaction, terrain, total_time_passed):
			_refresh_reusable_gathering_card(card, terrain, interaction, total_time_passed)
			return

	# 传回开始时快照的采集耗时，确保工具在长按中变化也不会改变已显示的等待成本。
	_execute_terrain_interaction(card, terrain, action_point_cost)

	if _is_reusable_gathering(interaction):
		_refresh_reusable_gathering_card(card, terrain, interaction, _get_current_total_time())


## 判断卡牌是否属于可重复采集地形，并返回刷新所需的快照数据。
##
## @param card 待判断的棋盘卡视图。
## @return 含 ok 标志的字典；命中时附带 terrain / interaction。
func _try_get_reusable_gathering(card: Node2D) -> Dictionary:
	var terrain: RefCounted = _read_ref_counted_property(card, "GetTerrainInstanceOrNull")
	var interaction: Resource = _get_terrain_interaction(terrain)
	if terrain == null or not _is_reusable_gathering(interaction):
		return {"ok": false}

	return {"ok": true, "terrain": terrain, "interaction": interaction}


## 按当前可采集状态刷新地形卡的交互可用性。
##
## @param card 目标地形卡。
## @param terrain 地形实例。
## @param interaction 地形交互资源。
## @param total_time_passed 当前游戏总时间点数。
## @return 无返回值。
func _refresh_reusable_gathering_card(
	card: Node2D,
	terrain: RefCounted,
	interaction: Resource,
	total_time_passed: int
) -> void:
	card.call("SetInteractionDisabled", not _can_harvest(interaction, terrain, total_time_passed))


## 执行地形交互的操作序列，等价旧 C# TerrainInteractionExecutor.Execute。
##
## @param card 触发交互的棋盘卡视图，也是掉落散射与源卡移除的目标。
## @param terrain 被交互的地形实例。
## @param effective_time_cost_override 长按开始时快照的有效采集时间；为 null 时由交互资源现场计算。
## @return 无返回值。
func _execute_terrain_interaction(
	card: Node2D,
	terrain: RefCounted,
	effective_time_cost_override: Variant
) -> void:
	var player: Node = _get_gameplay_player()
	var terrain_data: Resource = _read_terrain_data(terrain)
	var terrain_name: String = ""
	if terrain_data != null:
		terrain_name = _read_string_field(terrain_data, "CardName")
	print("[TerrainInteractionExecutor] Click terrain: %s" % terrain_name)

	var interaction: Resource = _get_terrain_interaction(terrain)
	if interaction == null:
		return

	# 生产地形交互资源全部是 GDScript 并实现 build_ops；旧 C# TerrainInteraction.BuildOps
	# 需要 C# 构建上下文，GDScript 侧无法表达，因此只保留同文本的硬失败提示作为兼容边界。
	if interaction.has_method("build_ops"):
		print(
			"[TerrainInteractionExecutor] Build GDScript ops from %s"
			% _interaction_display_name(interaction)
		)
		var built_ops: Variant = null
		if effective_time_cost_override != null:
			built_ops = interaction.call("build_ops", player, terrain, int(effective_time_cost_override))
		else:
			built_ops = interaction.call("build_ops", player, terrain)
		_apply_gdscript_ops(interaction, built_ops, terrain, card)
		return

	push_error(
		"地形交互资源 %s 未实现 BuildOps 或 build_ops，无法执行。"
		% _interaction_display_name(interaction)
	)


## 把 GDScript 交互资源返回的操作描述映射为运行时端口调用。
##
## @param interaction 返回描述的 GDScript 交互资源。
## @param built_ops GDScript 返回的 Dictionary 数组。
## @param terrain 当前地形实例，用于记录采集状态与遭遇来源。
## @param card 触发本次交互的棋盘卡视图，用于源卡移除与掉落散射起点。
## @return 无返回值。
func _apply_gdscript_ops(
	interaction: Resource,
	built_ops: Variant,
	terrain: RefCounted,
	card: Node2D
) -> void:
	if not (built_ops is Array):
		push_error("GDScript 地形交互的 build_ops 必须返回 Array[Dictionary]。\n")
		return

	var raw_ops: Array = built_ops
	print("[TerrainInteractionExecutor] GDScript ops count = %d" % raw_ops.size())
	for raw_op: Variant in raw_ops:
		if not (raw_op is Dictionary):
			push_error("GDScript 地形交互返回了非 Dictionary 操作，已跳过。\n")
			continue

		var op: Dictionary = raw_op
		var op_type: String = ""
		if op.has("type"):
			op_type = str(op["type"])

		match op_type:
			"pass_time":
				_apply_pass_time_op(int(op["amount"]))
			"spawn_loot":
				var drops: Array = _convert_drops(op["drops"])
				if not drops.is_empty():
					_board_controller.call("SpawnLootCards", drops, card.global_position)
			"mark_harvested":
				_mark_terrain_harvested(terrain)
			"check_gathering_encounter":
				_apply_check_gathering_encounter_op(_to_string_name(op["gathering_tag"]), terrain)
			"record_reusable_gathering":
				interaction.call("record_successful_harvest", terrain, _get_current_total_time())
			"enter_vault":
				_gameplay_port.call("RequestOpenWarehouse")
			"open_farming_panel":
				_gameplay_port.call("RequestOpenFarmingPanel", terrain)
			"spawn_monster":
				_apply_monster_spawn_op(op, terrain)
			"remove_source_card":
				_board_controller.call("RemoveCard", card)
			_:
				push_error("未知 GDScript 地形操作类型：%s。\n" % op_type)


## 执行时间流逝操作，等价旧 C# PassTimeOp。
##
## @param amount 要推进的游戏时间点数；非正数时不产生任何效果。
## @return 无返回值。
func _apply_pass_time_op(amount: int) -> void:
	if amount <= 0:
		return

	print("[PassTimeOp] Pass time %d" % amount)
	if _time_system != null and is_instance_valid(_time_system):
		_time_system.call("PassTime", amount)


## 执行采集遭遇检查，等价旧 C# CheckGatheringEncounterOp。
##
## @param gathering_tag 采集点资源标签；为空时直接返回。
## @param terrain 本次采集所在的地形实例。
## @return 无返回值。
func _apply_check_gathering_encounter_op(gathering_tag: StringName, terrain: RefCounted) -> void:
	if str(gathering_tag).is_empty():
		return

	print("Checking gathering encounter for tag: %s" % gathering_tag)
	var result: Variant = _resolve_gathering_encounter(gathering_tag)
	if not _is_triggered_encounter(result):
		return

	_gameplay_port.call(
		"RequestEncounter",
		terrain,
		_read_encounter_monsters(result),
		_read_encounter_message(result)
	)


## 执行固定怪物遭遇操作，等价旧 C# MonsterSpawnOpOp。
##
## @param op 操作的 Dictionary 描述，可能携带 monster 字段。
## @param terrain 本次遭遇所在的地形实例。
## @return 无返回值。
func _apply_monster_spawn_op(op: Dictionary, terrain: RefCounted) -> void:
	var monster: Variant = null
	if op.has("monster") and op["monster"] is Resource:
		monster = op["monster"]

	_gameplay_port.call("RequestEncounter", terrain, monster, "Boss Battle!")


## 把地形实例标记为已采集，等价旧 C# TerrainInstanceProtocol.SetBool(..., "IsHarvested", true)。
##
## @param terrain 地形实例；允许为空。
## @return 无返回值。
func _mark_terrain_harvested(terrain: RefCounted) -> void:
	if terrain == null:
		return

	# 生产地形实例已迁移到 GDScript，字段写入走动态通道；旧 C# TerrainInstance 的公开属性
	# 不是 Godot 属性，只能由保留的 C# 执行器写入，这里按字段存在性跳过以避免假写入。
	var current: Variant = terrain.get("IsHarvested")
	if current is bool:
		terrain.set("IsHarvested", true)


## 把 GDScript 操作里的掉落数组过滤为棋盘需要的跨语言堆叠数组。
##
## @param raw_drops 操作 Dictionary 中的 drops 字段。
## @return 保留有效物品堆叠原始引用的新数组。
func _convert_drops(raw_drops: Variant) -> Array:
	var drops: Array = []
	if not (raw_drops is Array):
		return drops

	for value: Variant in raw_drops:
		if value is RefCounted and _is_readable_item_stack(value):
			drops.append(value)

	return drops


## 判断物品堆叠是否满足跨语言协议，等价旧 C# ItemStackProtocol.TryRead。
##
## @param stack 旧 C# 或 GDScript 物品堆叠。
## @return 声明完整协议、物品非空且数量为正时返回 true。
func _is_readable_item_stack(stack: RefCounted) -> bool:
	if stack == null or not is_instance_valid(stack):
		return false
	if not stack.has_method("SetItem") or not stack.has_method("Clear"):
		return false

	var item: Variant = stack.get("Item")
	var amount: int = int(stack.get("Amount"))
	var is_empty: bool = bool(stack.get("IsEmpty"))
	return not is_empty and item != null and amount > 0


## 结算采集遭遇，等价旧 C# EncounterInteractionPort.ResolveGatheringEncounter。
##
## @param resource_tag 采集点资源标签。
## @return 遭遇结果对象；管理器缺失或协议不匹配时返回 null。
func _resolve_gathering_encounter(resource_tag: StringName) -> Variant:
	var encounter_chance_multiplier: float = _get_night_encounter_chance_multiplier(_get_gameplay_equipment())
	if _encounter_manager == null or not _encounter_manager.has_method("ResolveGatheringEncounter"):
		return null

	return _encounter_manager.call("ResolveGatheringEncounter", resource_tag, encounter_chance_multiplier)


## 判断跨语言遭遇结果是否触发了战斗。
##
## @param result 遭遇结果对象，可为空。
## @return Triggered 字段为 true 时返回 true。
func _is_triggered_encounter(result: Variant) -> bool:
	if not (result is Object) or not is_instance_valid(result):
		return false

	var triggered: Variant = (result as Object).get("Triggered")
	return triggered is bool and bool(triggered)


## 读取跨语言遭遇结果携带的怪物数组并过滤为战斗层资源数组。
##
## @param result 已触发的遭遇结果对象。
## @return 保持原顺序与对象身份的怪物资源数组。
func _read_encounter_monsters(result: Variant) -> Array[Resource]:
	if not (result is Object) or not is_instance_valid(result):
		return _convert_monsters(null)

	return _convert_monsters((result as Object).get("MonsterToSpawn"))


## 读取跨语言遭遇结果携带的提示文本。
##
## @param result 已触发的遭遇结果对象。
## @return 提示文本；类型不匹配时返回空字符串。
func _read_encounter_message(result: Variant) -> String:
	if not (result is Object) or not is_instance_valid(result):
		return ""

	var value: Variant = (result as Object).get("SpawnMessage")
	if value is String:
		return value

	return ""


## 从任一语言的装备组件读取夜晚遭遇倍率。
##
## @param equipment 实现稳定倍率查询协议的装备节点。
## @return 配置有效时返回装备倍率；节点缺失或返回值无效时返回中性倍率 1。
func _get_night_encounter_chance_multiplier(equipment: Node) -> float:
	if equipment == null or not is_instance_valid(equipment):
		return 1.0
	if not equipment.has_method("GetNightEncounterChanceMultiplier"):
		return 1.0

	var value: Variant = equipment.call("GetNightEncounterChanceMultiplier")
	if value is int or value is float:
		return float(value)

	return 1.0


## 进入战斗场景并等待过场结束，等价旧 C# WorldCombatScenePresenter.EnterCombatAsync。
##
## @param battle_deck 玩家本场战斗使用的技能卡组。
## @param monsters 本场战斗生成的怪物数组。
## @return 成功进入战斗返回 true；已处于过场中时返回 false 且不产生任何变化。
func _enter_combat(battle_deck: Array[Resource], monsters: Array[Resource]) -> bool:
	if _is_transitioning:
		return false

	_is_transitioning = true
	print("[WorldCombatScenePresenter] Entering Combat!")
	await _fade_out()

	var battle_instance: Node = _create_battle_instance(battle_deck, monsters)
	var battle_background: Sprite2D = _duplicate_current_background()
	if battle_background != null:
		battle_instance.add_child(battle_background)

	battle_instance.connect(BATTLE_ENDED_SIGNAL, Callable(self, "_on_battle_ended").bind(battle_instance))
	_world_root.add_child(battle_instance)
	_set_world_view_visible(false)

	await _fade_in()
	_is_transitioning = false
	return true


## 进入战斗并等待战斗结果，等价旧 C# EnterCombatAndWaitForResultAsync。
##
## @param battle_deck 玩家本场战斗使用的技能卡组。
## @param monsters 本场战斗生成的怪物数组。
## @return 战斗胜利时返回 true；无法进入战斗或失败时返回 false。
func _enter_combat_and_wait_for_result(
	battle_deck: Array[Resource],
	monsters: Array[Resource]
) -> bool:
	if _is_transitioning:
		return false

	# 清空上一次的结果标记，避免把上一场战斗的结果当作本场结果返回。
	_battle_result_ready = false
	await _enter_combat(battle_deck, monsters)
	while not _battle_result_ready:
		await get_tree().process_frame

	_battle_result_ready = false
	return _battle_result


## 战斗结束回调：过场退出战斗场景、恢复世界视图并记录结果。
##
## @param is_victory 本场战斗是否胜利。
## @param battle_instance 结束的战斗场景实例。
## @return 无返回值。
func _on_battle_ended(is_victory: bool, battle_instance: Node) -> void:
	if _is_transitioning:
		return

	_is_transitioning = true
	print("[WorldCombatScenePresenter] Combat Ended! Victory: %s" % str(is_victory))
	await _fade_out()

	if is_instance_valid(battle_instance):
		battle_instance.queue_free()

	_set_world_view_visible(true)
	await _fade_in()
	_is_transitioning = false
	_battle_result = is_victory
	_battle_result_ready = true


## 实例化战斗场景并按需注入卡组与怪物数据。
##
## @param battle_deck 玩家本场战斗使用的技能卡组；为空时不覆盖战斗场景导出值。
## @param monsters 本场战斗生成的怪物数组；为空时不覆盖战斗场景导出值。
## @return 尚未加入场景树的战斗场景根节点。
func _create_battle_instance(battle_deck: Array[Resource], monsters: Array[Resource]) -> Node:
	var battle_scene: PackedScene = load(BATTLE_SCENE_PATH) as PackedScene
	var battle_instance: Node = battle_scene.instantiate()
	if battle_deck != null and battle_deck.size() > 0:
		battle_instance.set("starting_deck_data", battle_deck)
	if monsters != null and monsters.size() > 0:
		battle_instance.set("starting_monster_data", monsters)

	return battle_instance


## 通过稳定方法协议调用生产 GDScript 背景解析器复制当前房间背景。
##
## @return 复制出的战斗背景；脚本或协议不可用时返回 null。
func _duplicate_current_background() -> Sprite2D:
	var resolver_script: GDScript = load(MAP_BACKGROUND_RESOLVER_SCRIPT_PATH) as GDScript
	if resolver_script == null:
		push_error("无法加载战斗背景解析器：%s" % MAP_BACKGROUND_RESOLVER_SCRIPT_PATH)
		return null

	var resolver: RefCounted = resolver_script.new() as RefCounted
	if resolver == null or not resolver.has_method("DuplicateCurrentBackground"):
		push_error("战斗背景解析器缺少 DuplicateCurrentBackground 协议。")
		return null

	var background: Variant = resolver.call("DuplicateCurrentBackground", _map_system)
	if background is Sprite2D:
		return background

	return null


## 等价旧 C# WorldViewVisibilityController：同时切换棋盘、地图、地图 CanvasLayer 与 HUD。
##
## @param visible 是否显示世界视图。
## @return 无返回值。
func _set_world_view_visible(visible: bool) -> void:
	_set_canvas_item_visible(BoardControllerPath, visible)
	_set_canvas_item_visible(MapSystemPath, visible)
	_set_canvas_layer_visible(MapCanvasLayerPath, visible)
	_set_canvas_layer_visible(HudLayerPath, visible)


## 切换一个 CanvasItem 节点的可见性。
##
## @param path 相对本节点的节点路径。
## @param visible 是否显示。
## @return 无返回值。
func _set_canvas_item_visible(path: NodePath, visible: bool) -> void:
	var node: CanvasItem = get_node(path) as CanvasItem
	if node == null:
		return

	node.visible = visible


## 切换一个 CanvasLayer 节点的可见性。
##
## @param path 相对本节点的节点路径。
## @param visible 是否显示。
## @return 无返回值。
func _set_canvas_layer_visible(path: NodePath, visible: bool) -> void:
	var node: CanvasLayer = get_node(path) as CanvasLayer
	if node == null:
		return

	node.visible = visible


## 播放一次过场淡出并等待完成信号。
##
## @return 无返回值。
func _fade_out() -> void:
	await _run_screen_transition("fade_out", &"fade_complete")


## 播放一次过场淡入并等待完成信号。
##
## @return 无返回值。
func _fade_in() -> void:
	await _run_screen_transition("fade_in", &"fade_in_complete")


## 调用过场 Autoload 的指定方法并等待对应完成信号。
##
## @param method_name 过场方法名，例如 fade_out。
## @param completed_signal 对应的完成信号名。
## @return 无返回值；过场缺失或未实现该方法时立即返回。
func _run_screen_transition(method_name: String, completed_signal: StringName) -> void:
	if _screen_transitions == null or not is_instance_valid(_screen_transitions):
		return
	if not _screen_transitions.has_method(method_name):
		return

	# 先建立一次性连接再发起过场，避免极短动画在连接之前就发出完成信号。
	var state: Dictionary = {"done": false}
	var on_completed: Callable = func() -> void:
		state["done"] = true
	_screen_transitions.connect(completed_signal, on_completed, CONNECT_ONE_SHOT)
	_screen_transitions.call(method_name)
	while not bool(state["done"]):
		await get_tree().process_frame


## 读取卡牌上的跨语言 RefCounted 返回值，等价旧 C# card.Call(...) as RefCounted。
##
## @param card 棋盘卡视图；允许为空。
## @param method_name 卡牌上返回 RefCounted 的方法名。
## @return 返回的对象；卡牌缺失、方法缺失或返回类型不符时返回 null。
func _read_ref_counted_property(card: Node2D, method_name: String) -> RefCounted:
	if card == null or not is_instance_valid(card):
		return null
	if not card.has_method(method_name):
		return null

	var value: Variant = card.call(method_name)
	if value is RefCounted:
		return value

	return null


## 读取地形实例上的地形配置资源，等价旧 C# TerrainInstanceProtocol.ReadTerrainData。
##
## @param terrain 地形实例；允许为空。
## @return 地形配置资源；缺失或类型不符时返回 null。
func _read_terrain_data(terrain: RefCounted) -> Resource:
	if terrain == null:
		return null

	var value: Variant = terrain.get("TerrainData")
	if value is Resource:
		return value

	return null


## 读取地形卡指向的交互行为资源。
##
## @param terrain 地形实例；允许为空。
## @return InteractionBehavior 资源；配置为空或字段缺失时返回 null。
func _get_terrain_interaction(terrain: RefCounted) -> Resource:
	var terrain_data: Resource = _read_terrain_data(terrain)
	if terrain_data == null:
		return null

	var value: Variant = terrain_data.get("InteractionBehavior")
	if value is Resource:
		return value

	return null


## 读取资源上的字符串字段。
##
## @param resource 目标资源；允许为空。
## @param field_name 字段名。
## @return 字符串字段值；缺失或类型不符时返回空字符串。
func _read_string_field(resource: Resource, field_name: String) -> String:
	if resource == null:
		return ""

	var value: Variant = resource.get(field_name)
	if value is String:
		return value

	return ""


## 读取交互资源本次占用的行动值，等价旧 C# GetInteractionActionPointCost。
##
## @param interaction 地形交互资源；允许为空。
## @return 实际消耗的行动值；不可用或配置无效时返回 0。
func _get_interaction_action_point_cost(interaction: Resource) -> int:
	if _is_reusable_gathering(interaction):
		return _get_reusable_effective_time_cost(interaction, _get_gameplay_equipment())
	if interaction == null:
		return 0

	var value: Variant = interaction.get("TimeCost")
	if value is int or value is float:
		return maxi(0, int(value))

	return 0


## 判断资源是否为旧 C# 或新 GDScript 可重复采集交互。
##
## 只按方法协议判定：旧 C# 垫片暴露 PascalCase 方法名，生产 GDScript 暴露 snake_case。
## 刻意不引用 C# 类型名 —— 语言身份判定会让脚本在 C# 垫片退役后直接解析失败。
##
## @param interaction 地形交互资源；允许为空。
## @return 资源实现了可重复采集 API 时返回 true。
func _is_reusable_gathering(interaction: Resource) -> bool:
	if interaction == null:
		return false

	return interaction.has_method(REUSABLE_GATHERING_CS_METHODS[REUSABLE_GATHERING_TIME_COST_INDEX]) \
		or interaction.has_method(REUSABLE_GATHERING_GD_METHODS[REUSABLE_GATHERING_TIME_COST_INDEX])


## 解析可重复采集协议要调用的方法名。
##
## 优先 PascalCase（旧 C# 垫片），否则用 snake_case（生产 GDScript）；用方法名探测
## 取代语言身份判定，让两种实现共用同一调用点。
##
## @param interaction 已确认为可重复采集的资源。
## @param index 协议数组下标：0 = 有效耗时，1 = 可采集判定。
## @return 实际需要调用的方法名。
func _resolve_reusable_gathering_method(interaction: Resource, index: int) -> StringName:
	if interaction.has_method(REUSABLE_GATHERING_CS_METHODS[index]):
		return REUSABLE_GATHERING_CS_METHODS[index]

	return REUSABLE_GATHERING_GD_METHODS[index]


## 调用两种语言实现的可重复采集有效耗时 API。
##
## @param interaction 可重复采集交互资源。
## @param equipment 当前玩家装备组件。
## @return 输入开始时应使用的有效采集耗时。
func _get_reusable_effective_time_cost(interaction: Resource, equipment: Node) -> int:
	return int(interaction.call(
		_resolve_reusable_gathering_method(interaction, REUSABLE_GATHERING_TIME_COST_INDEX),
		equipment
	))


## 调用两种语言实现的可重复采集可用性 API。
##
## @param interaction 可重复采集交互资源。
## @param terrain 地形实例。
## @param total_time_passed 当前游戏总时间点数。
## @return 资源仍可采集时返回 true。
func _can_harvest(interaction: Resource, terrain: RefCounted, total_time_passed: int) -> bool:
	return bool(interaction.call(
		_resolve_reusable_gathering_method(interaction, REUSABLE_GATHERING_CAN_HARVEST_INDEX),
		terrain,
		total_time_passed
	))


## 读取时间系统累计时间；缺失或类型不符时返回 0。
##
## @return 当前游戏总时间点数或 0。
func _get_current_total_time() -> int:
	if _time_system == null or not is_instance_valid(_time_system):
		return 0

	var value: Variant = _time_system.get("TotalTimePassed")
	if value is int or value is float:
		return int(value)

	return 0


## 从 GDScript GameplayPort 读取当前玩家节点。
##
## @return 生产玩家实例；属性缺失或类型不符时返回 null。
func _get_gameplay_player() -> Node:
	if _gameplay_port == null or not is_instance_valid(_gameplay_port):
		return null

	var value: Variant = _gameplay_port.get("Player")
	if value is Node:
		return value

	return null


## 读取生产玩家身上的装备组件节点。
##
## @return 装备组件节点；玩家缺失或字段缺失时返回 null。
func _get_gameplay_equipment() -> Node:
	var player: Node = _get_gameplay_player()
	if player == null:
		return null

	var value: Variant = player.get("Equipment")
	if value is Node:
		return value

	return null


## 调用 GameplayPort 的稳定卡组方法，并显式过滤 GDScript 动态数组。
##
## @return 保持顺序和 Resource 身份的技能卡数组。
func _get_player_skill_cards() -> Array[Resource]:
	var cards: Array[Resource] = []
	if _gameplay_port == null or not is_instance_valid(_gameplay_port):
		return cards
	if not _gameplay_port.has_method("GetPlayerSkillCards"):
		return cards

	var raw_cards: Variant = _gameplay_port.call("GetPlayerSkillCards")
	if raw_cards is Array:
		return _convert_skill_cards(raw_cards)

	return cards


## 将 GDScript 技能卡数组过滤为战斗层要求的通用 Resource 数组。
##
## @param raw_cards GameplayPort 信号或方法返回的动态数组。
## @return 过滤无效元素后保持原顺序和 Resource 身份的数组。
func _convert_skill_cards(raw_cards: Array) -> Array[Resource]:
	var cards: Array[Resource] = []
	for value: Variant in raw_cards:
		if value is Resource and (value as Resource).has_method("ApplyEffect"):
			cards.append(value as Resource)

	return cards


## 将 GDScript 怪物数组过滤为战斗层要求的强类型数组，等价旧 C# MonsterDataProtocol.FilterMonsters。
##
## @param raw_monsters GameplayPort 信号返回的动态数组；允许为空或非数组。
## @return 过滤无效元素后保持原顺序和 Resource 身份的怪物数组。
func _convert_monsters(raw_monsters: Variant) -> Array[Resource]:
	var monsters: Array[Resource] = []
	if not (raw_monsters is Array):
		return monsters

	for value: Variant in raw_monsters:
		if _is_monster_data(value):
			monsters.append(value as Resource)

	return monsters


## 判断资源是否为旧 C# MonsterData 或迁移后的 GDScript 怪物数据。
##
## 两侧实现共用同一组导出字段，因此判定只扫字段面（属性表）。
##
## @param value 待判断的动态值。
## @return 属于两种怪物数据实现之一时返回 true。
func _is_monster_data(value: Variant) -> bool:
	if not (value is Resource):
		return false

	var resource: Resource = value
	var present: Dictionary = {}
	for property: Dictionary in resource.get_property_list():
		present[StringName(property.get("name", ""))] = true

	for field: StringName in MONSTER_DATA_REQUIRED_FIELDS:
		if not present.has(field):
			return false

	return true


## 把动态值转换为 StringName，兼容 String 与 StringName 两种封送结果。
##
## @param value 动态值。
## @return 对应的 StringName；无法转换时返回空 StringName。
func _to_string_name(value: Variant) -> StringName:
	if value is StringName:
		return value
	if value is String:
		return StringName(value)

	return &""


## 生成交互资源的可读名称，用于迁移期日志与报错文本。
##
## @param resource 交互资源；允许为空。
## @return GDScript/C# 脚本文件名，缺失时返回资源的原生类名。
func _interaction_display_name(resource: Resource) -> String:
	if resource == null:
		return ""

	var resource_script: Script = resource.get_script() as Script
	if resource_script != null and not resource_script.resource_path.is_empty():
		return resource_script.resource_path.get_file().get_basename()

	return resource.get_class()
