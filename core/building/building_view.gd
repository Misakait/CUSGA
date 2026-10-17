extends Node2D

## 建筑地面表现；只负责图标、占地提示与碰撞，不拥有库存或交互业务。

## 建筑实体所在碰撞层，默认第 6 层，与地图障碍和玩家掩码一致。
@export_flags_2d_physics var CollisionLayer: int = 32

## 视觉动作参数资产；与地形卡共用同一份，保证两条破坏长按的抖动手感一致。
@export var MotionConfig: Resource = preload("res://resources/interaction/item_motion_config.tres")

## 当前建筑配置；共享资源只读，运行时状态保留在仓库记录中。
var _data: Resource
## 是否为预览；预览禁用实体碰撞，避免影响落点校验。
var _preview: bool = false
## 当前是否可放置；决定预览占地颜色。
var _valid: bool = true
## 当前是否为最近可交互目标；决定高亮轮廓。
var _focused: bool = false
## 拆除长按期间的贴图抖动；在 _ready 中按动作参数构造。
var _shake: DestroyShake = null
## 建筑图标；拆除抖动的目标。
var _icon: Sprite2D = null
## 不参与抖动的进度锚点；拆除圆环锚定它而不是 _icon，否则图标一抖圆环就会跟着抖。
var _progress_anchor: Marker2D = null


## 解析固定子节点并按动作参数构造拆除抖动。
## 无参数，无返回值。
func _ready() -> void:
	_icon = get_node_or_null("Icon") as Sprite2D
	_progress_anchor = get_node_or_null("ProgressAnchor") as Marker2D
	# 抖动参数与地形卡共用同一资产；资产缺失时由组件自带兜底值接管。
	_shake = DestroyShake.new(
		_icon,
		_motion_float("DestroyShakeAmplitude", DestroyShake.DEFAULT_AMPLITUDE),
		_motion_float("DestroyShakeStepSeconds", DestroyShake.DEFAULT_STEP_SECONDS)
	)
	DestroyShake.SyncAnchor(_icon, _progress_anchor)


## 退出时终止抖动，避免 Tween 与贴图偏移残留到下一次房间重建。
## 无参数，无返回值。
func _exit_tree() -> void:
	if _shake != null:
		_shake.Stop()


## 切换「正在被拆除」的抖动表现；重复调用同一状态不产生额外影响。
##
## 只抖图标节点的本地 position，不改变根节点位置、旋转、碰撞层与占地轮廓，
## 因此独立的进度锚点在抖动期间保持逐帧静止。
##
## 参数 destroying：是否正在被拆除，无返回值。
func SetDestroying(destroying: bool) -> void:
	if _shake == null:
		return
	if destroying:
		_shake.Start()
	else:
		_shake.Stop()


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
	# 锚点位置由图标纹理与缩放共同推导，二者都在上面才确定，因此必须在这里重算，
	# 否则圆环会停在旧尺寸建筑的右下角。
	DestroyShake.SyncAnchor(icon, _progress_anchor)
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


## 读取动作参数资产中的浮点字段；资产缺失或字段类型不符时回退到兜底值。
##
## 参数 field：字段名；参数 fallback：兜底值。返回字段值或兜底值。
func _motion_float(field: StringName, fallback: float) -> float:
	if MotionConfig == null:
		return fallback
	var value: Variant = MotionConfig.get(field)
	return float(value) if value is float or value is int else fallback
