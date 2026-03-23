extends Resource
class_name Snapper

@export var snap_distance: float = 100.0   # 吸附阈值，像素
@export var enable_snap: bool = true       # 是否启用吸附

func snap_to_slots(target_node: Node, slots: Array[Node]) -> void:
	if not enable_snap or slots.is_empty():
		return

	var closest_slot: Node = null
	var closest_dist: float = INF

	for slot in slots:
		if slot is Control or slot is Node2D:
			var dist = target_node.position.distance_to(slot.position)
			if dist < closest_dist:
				closest_dist = dist
				closest_slot = slot

	if closest_slot and closest_dist <= snap_distance:
		target_node.position = closest_slot.position
