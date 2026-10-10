extends TextureRect

# 是否正在拖拽
var is_dragging: bool = false
# 记录鼠标点击时的初始偏移，用于平滑拖拽
var drag_offset: Vector2 = Vector2.ZERO

@onready var parent_node: Control = get_parent() as Control

func _ready() -> void:
	# 确保父节点和当前节点尺寸合法，若图片比视窗还小，则无需限制
	if size.x < parent_node.size.x or size.y < parent_node.size.y:
		push_warning("子图片尺寸应当大于或等于父遮罩尺寸以获得最佳拖拽效果")

func _gui_input(event: InputEvent) -> void:
	# 检测鼠标左键（或触摸屏）按下与释放
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			# 记录鼠标相对于图片左上角的位置
			drag_offset = event.position
		else:
			is_dragging = false
			
	# 检测鼠标在按下状态下的移动
	elif event is InputEventMouseMotion and is_dragging:
		# 计算新的目标位置：全局鼠标位置 - 点击时的相对偏移 - 父节点全局位置
		var target_pos = event.global_position - drag_offset - parent_node.global_position
		
		# 边界限制 (Clamp)：防止拖拽过度导致“露白”
		# X 轴范围：最大 0（左边贴齐），最小为 父宽 - 子宽（右边贴齐）
		var min_x = parent_node.size.x - size.x
		var max_x = 0.0
		# Y 轴范围同理
		var min_y = parent_node.size.y - size.y
		var max_y = 0.0
		
		# 实施位置限制
		position.x = clamp(target_pos.x, min_x, max_x)
		position.y = clamp(target_pos.y, min_y, max_y)
