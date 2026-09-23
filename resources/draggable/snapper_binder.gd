extends Node2D
class_name SnapperBinder

@export var target_snapper: Snapper        # 在 Inspector 中拖入一个 Snapper 资源
@export var snap_nodes: Array[Node2D] = [] # 在 Inspector 中拖入多个 Node2D 节点

func _ready():
	update_snapper_positions()
	
func update_snapper_positions():
	if target_snapper:
		# 重建吸附坐标前先丢弃上一批场景实例遗留的吸附记录（原因见
		# Snapper.prune_snapped_cards 的说明）。本函数在 _ready 里调用，此刻
		# 本实例的卡牌刚进树、尚未参与任何拖拽，因此清理不会误伤本轮的有效记录；
		# 而已经退场的那些实例，其记录必须在这里被清掉，否则吸附点会被永久占用。
		target_snapper.prune_snapped_cards()
		target_snapper.snap_positions.clear()
		for node in snap_nodes:
			if node:
				target_snapper.snap_positions.append(node.global_position)
