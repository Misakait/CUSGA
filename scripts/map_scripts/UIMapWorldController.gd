extends Node

## 地图世界 Controller。
##
## Controller 只解释玩家位置和旧 UI 的进入房间意图，然后调用 Model。
## 房间节点实例化和 UI 更新由 UIMapWorldView 监听 Model 信号完成。

@export var player_path: NodePath = NodePath("")

var _map_control: Node = null
var _map_world_model: Node = null
var _map_world_view: Node = null
var _player: Node2D = null
var _time_system: Node = null
var _is_transition_in_progress: bool = false
var _last_valid_position: Vector2i = Vector2i(-999999, -999999)
var _last_observed_position: Vector2i = Vector2i(-999999, -999999)

func _ready() -> void:
	_time_system = get_node_or_null("/root/TimeSystem")
	_map_control = get_parent()
	_map_world_model = get_node_or_null("../MapWorldModel")
	_map_world_view = get_node_or_null("../MapInstantiator")
	if _map_world_view == null:
		_map_world_view = get_node_or_null("../UIMapWorldView")
	_resolve_player()
	if _map_world_model != null:
		_last_valid_position = _map_world_model.get(&"current_position")
		_last_observed_position = _last_valid_position

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_resolve_player()
		return
	if _map_world_model == null:
		return

	# 房间原点属于 View 的本地坐标系，父节点移动或缩放后仍须按同一坐标系判断跨房。
	var map_world_position := _player.global_position
	if _map_world_view is Node2D:
		map_world_position = (_map_world_view as Node2D).to_local(_player.global_position)
	var candidate: Vector2i = _map_world_model.call(&"map_position_for_world", map_world_position)
	if candidate == _last_observed_position:
		return
	# 无效坐标也记录观察结果，避免玩家停在边界时每帧重复加载和校验。
	_last_observed_position = candidate
	if not bool(_map_world_model.call(&"has_room", candidate)):
		# 物理阻挡由场景瓦片负责；非法坐标不能改变当前房间，也不能触发传送修正。
		return

	request_room_transition(candidate)

## 将一个进入房间意图交给 Model；View 通过 Model 信号更新显示。
##
## @param position 目标地图坐标。
## @return Model 接受目标坐标时返回 true；真实换房成功后只结算一次行动值。
func request_room_transition(position: Vector2i) -> bool:
	if _map_world_model == null or _is_transition_in_progress:
		return false
	var previous_position: Vector2i = _map_world_model.get(&"current_position")
	# Model 信号会同步更新窗口与内容；阻止这些回调重入并产生重复收费。
	_is_transition_in_progress = true
	var accepted := bool(_map_world_model.call(&"try_enter_room", position))
	if accepted:
		_last_valid_position = position
		_last_observed_position = position
		if previous_position != position:
			if _time_system != null and _time_system.has_method(&"PassMapMoveTime"):
				_time_system.call(&"PassMapMoveTime")
			else:
				push_warning("跨房成功但未找到 TimeSystem，无法推进本次行动时间。")
	_is_transition_in_progress = false
	return accepted

func _resolve_player() -> void:
	if _map_control == null:
		return

	var player_value: Variant = null
	if not player_path.is_empty():
		player_value = _map_control.get_node_or_null(player_path)
	if player_value == null:
		player_value = _map_control.get(&"player_char")
	_player = player_value as Node2D

## 未来接口：根据当前房间 TileMap 的限制区域判断是否允许跨界。
## 保留额外移动规则接口；当前由瓦片碰撞阻挡，跨房流程不调用本接口。
##
## @param from_position 离开的地图坐标。
## @param to_position 进入的地图坐标。
## @param player_position 玩家准备跨界时的世界坐标。
## @return 当前阶段始终返回 true。
func can_enter_room_with_boundaries(
	_from_position: Vector2i,
	_to_position: Vector2i,
	_player_position: Vector2
) -> bool:
	return true

## 未来接口：接入通道驻守战斗。
## 当前跨房间会结算行动值，但不通过这个预留接口触发战斗。
##
## @param _from_position 离开的地图坐标。
## @param _to_position 进入的地图坐标。
## @return 当前阶段返回 false，表示未请求战斗。
func request_passage_guard_encounter(_from_position: Vector2i, _to_position: Vector2i) -> bool:
	return false
