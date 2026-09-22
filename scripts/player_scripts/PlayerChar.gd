extends CharacterBody2D

@export var player_data: PlayerData
@onready var camera: Camera2D = $"Camera2D"
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var anim_state = $AnimationTree.get("parameters/playback")
@onready var sprite: Sprite2D = $"Visuals"

func _ready() -> void:
	if player_data == null:
		print("你完蛋咯，出bug咯")
		player_data = PlayerData.new()
	
	if anim_tree:
		anim_tree.active = true

func move_player(_delta: float) -> void:
	var move_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if move_dir != Vector2(0,0):
		sprite.flip_h = false if move_dir.x > 0 else true
	velocity.x = lerp(velocity.x, player_data.walk_speed * move_dir.x , _delta * 12)
	velocity.y = lerp(velocity.y, player_data.walk_speed * move_dir.y , _delta * 12)
	print(velocity.x,"      ",velocity.y)
