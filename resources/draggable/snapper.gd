extends Resource
class_name Snapper

@export_group("吸附设置")
@export var snap_positions: Array[Vector2] = []   # 吸附点坐标数组
@export var snap_radius: float = 80.0             # 吸附范围半径
@export var tween_duration: float = 0.3           # 缓动时长
@export var allow_multiple: bool = false          # 是否允许多个卡牌吸附到同一点

var snapped_cards: Dictionary = {}   # {card: snap_position}

func get_nearest_snap_position(card) -> Vector2:
	var nearest: Vector2 = Vector2.ZERO
	var min_dist: float = INF
	for pos in snap_positions:
		var dist = card.global_position.distance_to(pos)
		if dist < min_dist and dist <= snap_radius:
			min_dist = dist
			nearest = pos
	return nearest

func can_snap(card, pos: Vector2) -> bool:
	if pos == Vector2.ZERO:
		return false
	if allow_multiple:
		return true
	return not snapped_cards.values().has(pos)

func snap_card(card) -> void:
	var pos = get_nearest_snap_position(card)
	if can_snap(card,pos):
		var tween = card.create_tween()
		tween.tween_property(card, "global_position", pos, tween_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		snapped_cards[card] = pos
	else:
		release_card(card)

func release_card(card) -> void:
	if snapped_cards.has(card):
		snapped_cards.erase(card)
