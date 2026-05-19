extends Node

@export var player: Node
@export var canvas_layer: CanvasLayer

signal on_entered_room(position: Vector2i, scene: Node2D)

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
	for i in ItemsControl.warehouse_to_player.size():
		var item_data: ItemData = ItemsControl.warehouse_to_player[i]
		var amount: int = ItemsControl.warehouse_to_player_cnt[i]
		player._inventory.AddItem(item_data,amount)

	ItemsControl.warehouse_to_player.clear()
	ItemsControl.warehouse_to_player_cnt.clear()

func _on_map_instantiator_entered_room(position: Vector2i, scene: Node2D) -> void:
	emit_signal(&"on_entered_room", position, scene)
