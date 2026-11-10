extends Node

## 只在单场战斗中收集怪物死亡掉落；胜利后交给世界棋盘生成可拾取物。
## 掉落事件总线路径，使用节点协议以便独立测试。
const EVENT_BUS_PATH: NodePath = ^"/root/GlobalEventBus"
## 战斗中暂存的物品堆叠，保留原始装备实例属性。
var _pending: Array[RefCounted] = []
## 恢复探索时负责生成掉落卡的棋盘。
var _board: Node
## 掉落生成原点；战斗坐标与世界坐标不同，故使用玩家世界位置。
var _player: Node2D
## 当前会话的掉落事件总线。
var _event_bus: Node
## 防止重复战斗结束信号导致重复生成。
var _finished: bool = false

## 设置战斗结果的世界投放依赖。
## 参数 board：棋盘控制器；player：世界中的玩家节点。返回值：无。
func Configure(board: Node, player: Node2D) -> void:
	_board = board
	_player = player

## 订阅怪物死亡掉落与本场战斗结束信号。
## 返回值：无。
func _ready() -> void:
	_event_bus = get_node_or_null(EVENT_BUS_PATH)
	if _event_bus != null and _event_bus.has_signal("on_entity_dropped"):
		_event_bus.connect("on_entity_dropped", _on_entity_dropped)
	var battle: Node = get_parent()
	if battle != null and battle.has_signal("battle_ended"):
		battle.connect("battle_ended", _on_battle_ended)

## 离开战斗时取消全局订阅，防止下一场战斗重复收集。
## 返回值：无。
func _exit_tree() -> void:
	if is_instance_valid(_event_bus) and _event_bus.has_signal("on_entity_dropped") and _event_bus.is_connected("on_entity_dropped", _on_entity_dropped):
		_event_bus.disconnect("on_entity_dropped", _on_entity_dropped)

## 将单次死亡生成的堆叠暂存到本场战斗。
## 参数 _position：战斗中的位置；stacks：掉落堆叠数组。返回值：无。
func _on_entity_dropped(_position: Vector2, stacks: Variant) -> void:
	if _finished or not (stacks is Array):
		return
	for stack: Variant in stacks:
		if stack is RefCounted and not bool(stack.get("IsEmpty")):
			_pending.append(stack)

## 胜利后在玩家世界位置生成掉落；失败时不向世界投放。
## 参数 is_victory：战斗是否胜利。返回值：无。
func _on_battle_ended(is_victory: bool) -> void:
	if _finished:
		return
	_finished = true
	if is_victory and not _pending.is_empty() and is_instance_valid(_board) and is_instance_valid(_player):
		_board.call("SpawnLootCards", _pending, _player.global_position)
	_pending.clear()
