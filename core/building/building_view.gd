extends Node2D

## 建筑地面表现；只负责图标、占地提示与碰撞，不拥有库存或交互业务。

## 建筑实体所在碰撞层，默认第 6 层，与地图障碍和玩家掩码一致。
@export_flags_2d_physics var CollisionLayer: int = 32

## 当前建筑配置；共享资源只读，运行时状态保留在仓库记录中。
var _data: Resource
## 是否为预览；预览禁用实体碰撞，避免影响落点校验。
var _preview: bool = false
## 当前是否可放置；决定预览占地颜色。
var _valid: bool = true
## 当前是否为最近可交互目标；决定高亮轮廓。
var _focused: bool = false


## 绑定建筑显示；data 为建筑配置，preview 表示是否仅预览，无返回值。
func Configure(data: Resource, preview: bool = false) -> void:
	_data = data
	_preview = preview
	# 图标按占地范围等比缩放，资源分辨率不改变世界空间占用。
	var icon: Sprite2D = get_node("Icon") as Sprite2D
	# 建筑的世界像素占地尺寸，与预览和碰撞规则共用。
	var footprint: Vector2 = data.get("Footprint")
	icon.texture = data.get("CardIcon") as Texture2D
	if icon.texture != null:
		# 每张卡使用自身纹理大小，避免硬编码篝火图片分辨率。
		var texture_size: Vector2 = icon.texture.get_size()
		icon.scale = Vector2.ONE * minf(footprint.x / texture_size.x, footprint.y / texture_size.y)
	# 每个实体创建独立形状，避免修改共享子资源影响同类建筑。
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = footprint
	(get_node("Body/CollisionShape2D") as CollisionShape2D).shape = shape
	(get_node("Body") as StaticBody2D).collision_layer = 0 if preview else CollisionLayer
	queue_redraw()


## 更新预览是否合法；valid 为本帧校验结果，无返回值。
func SetPlacementValid(valid: bool) -> void:
	_valid = valid
	modulate = Color(0.5, 1.0, 0.65, 0.7) if valid else Color(1.0, 0.35, 0.3, 0.7)
	queue_redraw()


## 更新交互目标高亮；focused 为是否被选中，无返回值。
func SetFocused(focused: bool) -> void:
	if _focused == focused:
		return
	_focused = focused
	queue_redraw()


## 绘制占地轮廓；无参数，无返回值。
func _draw() -> void:
	if _data == null or not (_preview or _focused):
		return
	# 占地预览与规则服务使用完全相同的中心和尺寸。
	var footprint: Vector2 = _data.get("Footprint")
	var tint: Color = Color(0.4, 1.0, 0.6) if _valid else Color(1.0, 0.3, 0.25)
	draw_rect(Rect2(-footprint / 2.0, footprint), tint, false, 2.0)
