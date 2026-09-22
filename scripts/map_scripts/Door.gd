extends Area2D

@export_file("*.tscn") var target_scene: String
@export var target_scene_id: String
@export var target_door_id: String
@export var cool_down_time: float = 1
var ready_to_change: bool = false
var player: Node2D

var cool_down_timer: float = 0.0
var offset_node: Node2D
var offset: Vector2


func _ready() -> void:
	if get_child_count() >= 2:
		offset_node = get_children()[1]
		offset = offset_node.position
	else:
		offset = Vector2(0,0)
	
	cool_down_timer = cool_down_time
	ready_to_change = false
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
func _physics_process(delta: float) -> void:
	cool_down_timer = max(cool_down_timer - delta, 0)
	if ready_to_change and cool_down_timer == 0:
		_on_body_entered(player)
	
func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		if cool_down_timer > 0:
			ready_to_change = true
			player = body
			return
		SceneManager._switch_to(target_scene_id, target_scene_id)
		SceneManager.target_spawn_id = target_door_id
		
func _on_body_exited(body: Node2D) -> void:
	ready_to_change = false
	body = null
