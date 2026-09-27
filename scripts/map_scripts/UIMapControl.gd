extends Node

## 地图 UI 的根控制器。
##
## 该节点只负责组合 Model、World View 和小地图 View，并向外转发进入房间事件。
## 地图状态的修改仍由 UIMapWorldController 调用 MapWorldModel 完成。

@export var player: Node
@export var player_char: CharacterBody2D
@export var canvas_layer: CanvasLayer

signal on_entered_room(position: Vector2i, scene: Node2D)

@onready var map_world_view: Node = $MapInstantiator
@onready var map_world_model: Node = $MapWorldModel
@onready var map_little: Node = $MapLittle
@onready var mini_map: Control = $CanvasLayer/MiniMap
@onready var large_map: CanvasLayer = $LargeMap

func _ready() -> void:
	_bind_map_views()
	if not map_world_view.has_signal(&"on_entered_room"):
		push_error("UIMapWorldView 缺少 on_entered_room 信号")
		return

	map_world_view.connect(
		&"on_entered_room",
		Callable(self, "_on_map_world_view_entered_room")
	)
	# View 先于根节点 ready；延迟补发初始房间，保证小地图和棋盘不会漏掉首个状态。
	var initial_scene: Node2D = map_world_view.get(&"current_scene") as Node2D
	if initial_scene != null:
		call_deferred(
			"_on_map_world_view_entered_room",
			map_world_view.get(&"current_position"),
			initial_scene
		)
	# 开局背包初始化由 Main/RunStartInitializer 统一执行；地图 UI 不读取带入栏或玩家背包。


func _exit_tree() -> void:
	if map_world_view == null or not is_instance_valid(map_world_view):
		return
	var callable: Callable = Callable(self, "_on_map_world_view_entered_room")
	if map_world_view.has_signal(&"on_entered_room") and map_world_view.is_connected(
		&"on_entered_room",
		callable
	):
		map_world_view.disconnect(&"on_entered_room", callable)


func _bind_map_views() -> void:
	for view: Node in [map_little, mini_map, large_map]:
		if view == null or not view.has_method(&"bind_model"):
			push_error("UIMapControl 的地图 View 缺少 bind_model(model) 入口。")
			continue
		view.call(&"bind_model", map_world_model)

func _on_map_world_view_entered_room(position: Vector2i, scene: Node2D) -> void:
	if map_little != null and map_little.has_method(&"update_current_position"):
		map_little.call(&"update_current_position", position)
	emit_signal(&"on_entered_room", position, scene)
