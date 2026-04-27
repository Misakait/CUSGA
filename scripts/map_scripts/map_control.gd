extends Node

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

func _on_map_instantiator_entered_room(position: Vector2i, scene: Node2D) -> void:
	emit_signal(&"on_entered_room", position, scene)
