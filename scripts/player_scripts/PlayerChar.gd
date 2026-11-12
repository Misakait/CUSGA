extends CharacterBody2D

@export var player_data: PlayerData
## 与物品交互时保留的移动速度比例；0.2 表示降低 80%，只影响运行时速度，不写入资源或存档。
@export_range(0.0, 1.0, 0.01) var item_interaction_speed_multiplier: float = 0.2
@onready var camera: Camera2D = $"Camera2D"
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var anim_state = $AnimationTree.get("parameters/playback")
@onready var sprite: Sprite2D = $"Visuals"

## 当前是否处于物品交互减速状态；同一时刻只允许一个世界物品长按，因此用布尔量即可。
var _item_interaction_active: bool = false

func _ready() -> void:
	if player_data == null:
		print("你完蛋咯，出bug咯")
		player_data = PlayerData.new()
	
	if anim_tree:
		anim_tree.active = true

## 进入物品交互减速状态；重复调用保持同一状态，避免倍率被多次叠乘。
## @return 无返回值。
func BeginItemInteraction() -> void:
	_item_interaction_active = true

## 退出物品交互减速状态；重复调用不会产生负倍率或残留减速。
## @return 无返回值。
func EndItemInteraction() -> void:
	_item_interaction_active = false

## 返回当前实际用于行走的速度，供键盘移动与鼠标移动共用同一口径。
## @return 基础 `walk_speed` 在物品交互期间乘以配置倍率，其余情况原样返回。
func get_effective_walk_speed() -> float:
	if player_data == null:
		return 0.0
	var speed: float = player_data.walk_speed
	if _item_interaction_active:
		speed *= item_interaction_speed_multiplier
	return maxf(speed, 0.0)

func move_player(_delta: float) -> void:
	var move_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if move_dir != Vector2(0,0):
		sprite.flip_h = false if move_dir.x > 0 else true
	var speed: float = get_effective_walk_speed()
	velocity.x = lerp(velocity.x, speed * move_dir.x , _delta * 12)
	velocity.y = lerp(velocity.y, speed * move_dir.y , _delta * 12)
