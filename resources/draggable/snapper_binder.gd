extends Node2D
class_name SnapperBinder

@export var target_snapper: Snapper        # 在 Inspector 中拖入一个 Snapper 资源
@export var snap_nodes: Array[Node2D] = [] # 在 Inspector 中拖入多个 Node2D 节点

func _ready():
	update_snapper_positions()

func update_snapper_positions():
	if target_snapper:
		target_snapper.snap_positions.clear()
		for node in snap_nodes:
			if node:
				target_snapper.snap_positions.append(node.global_position)
