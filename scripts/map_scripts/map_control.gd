extends Node

@export var player: Node
@export var player_char: CharacterBody2D
@export var canvas_layer: CanvasLayer

## 说明：`player` 现已不再被本脚本读取（带入逻辑迁往 core/gameflow/run_start_initializer.gd），
## 但 `scenes/Main.tscn` 仍把它作为场景属性引用，且后续若需要从地图侧查询玩家状态可直接复用。
## 这里刻意保留导出与既有注释，不做重命名或删除。

signal on_entered_room(position: Vector2i, scene: Node2D)

@onready var door_controller: Node2D = $"DoorController"
@onready var map_instantiator: Node = $MapInstantiator

func _ready() -> void:
	if not map_instantiator.has_signal(&"on_entered_room"):
		push_error("MapInstantiator 缺少 on_entered_room 信号")
		return

	map_instantiator.connect(
		&"on_entered_room",
		Callable(self, "_on_map_instantiator_entered_room")
	)

	
	#将局外仓库里的东西带入游戏
	#【修订说明】该职责已迁移到 `core/gameflow/run_start_initializer.gd`（挂在 Main.tscn 上）。
	#迁移原因有二：①地图控制器不该承担「开局角色与背包初始化」；②原先这里直接读写玩家
	#私有字段 `_inventory`，绕过了玩家组件的稳定方法协议。
	#带入栏的权威状态与「带入即消耗」语义现在分别由 ItemsControl 与 RunStartInitializer 维护，
	#本控制器不再触碰玩家背包。
	
	# 把表现层的playerchar给controller
	door_controller.player = player_char

func _on_map_instantiator_entered_room(position: Vector2i, scene: Node2D) -> void:
	emit_signal(&"on_entered_room", position, scene)
