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

## 丢弃所有已失效的吸附记录。
## @remarks
## `snapped_cards` 以**卡牌节点**为键，而承载它的本对象是内联在 `main_menu.tscn`
## 里的子资源，会被该场景的**所有实例共享**；同时 `SceneManager` 缓存场景、只做
## remove/add 而不销毁，上一批实例的卡牌节点可能在场景退场后仍然存活（孤儿节点）。
## 两者叠加后，旧记录会永久占住吸附点坐标，使 `can_snap()` 对新实例的卡牌恒返回
## false —— 表现为主菜单里任何卡牌拖到吸附点都毫无反应，既进不了游戏也打不开仓库。
##
## 因此这里确立的不变量是：**吸附记录只能属于此刻仍在场景树上的卡牌**。
## @return int 本次被清理掉的记录条数，便于调用方断言与调试。
func prune_snapped_cards() -> int:
	var removed := 0
	for card in snapped_cards.keys():
		# 先判 is_instance_valid 再做类型收窄：对象若已被释放，`as Node` 会得到 null，
		# 顺序颠倒会让本函数自己变成运行期错误，那正是要修掉的失效引用反而清不掉。
		if not is_instance_valid(card) or not (card as Node).is_inside_tree():
			snapped_cards.erase(card)
			removed += 1

	return removed
